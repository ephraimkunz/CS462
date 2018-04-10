ruleset store_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, get_all_orders, get_bids, get_assigned_orders, get_completed_orders
    }

    global {
        __testing = {"events": [
            {
                "domain": "order", "type": "new", "attrs": ["phone", "description"]
            }],

            "queries": [
                {"name": "get_all_orders"}, {"name": "get_bids"}, {"name": "get_assigned_orders"}, {"name": "get_completed_orders"}
            ]
        }

        get_assigned_orders = function() {
            ent:orders.filter(function(a) {
                not a{"assigned_driver"}.isnull() && a{"delivered_at"}.isnull();
            });
        }

        get_completed_orders = function() {
            ent:orders.filter(function(a) {
                not a{"delivered_at"}.isnull()
            });
        }

        get_driver = function() {
            subs = Subscriptions:established("Rx_role","driver").klog("Drivers:");
            
            // Return a random driver from this list of drivers the store knows about
            rand_sub = random:integer(subs.length() - 1);
            subs[rand_sub]
        }

        order_by_id = function(id) {
            ent:orders{id}
        }

        get_all_orders = function() {
            ent:orders
        }

        get_bids = function() {
            ent:bids
        }

        chooseBidForOrder = function(orderId) {
            filtered = ent:bids.filter(function(a){a{"id"} == orderId}).klog("Filtered:");

            // TODO: Replace with distance API
            sorted = filtered.sort(function(a, b) { a{"dist"} < b{"dist"}  => -1 |
                            a{"dist"} == b{"dist"} =>  0 |
                                       1
            }).klog("Sorted:");
            sorted[0];
        }

        getRejectedBids = function(acceptedBid) {
            filtered = ent:bids.filter(function(a){
                a{"id"} == acceptedBid{"id"} && a{"driverEci"} != acceptedBid{"driverEci"}
            });
            filtered
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:bids := [];
            ent:orders := {};
            ent:bidWindowTime := 10;
        }
    }

    // Customer order triggers this rule
    rule new_order {
        select when order new 
        pre {
            // Create unique identifier for this new order
            id = random:uuid()
            customer_phone = event:attr("phone")
            description = event:attr("description")

            new_order = {
                "id": id,
                "customer_phone": customer_phone,
                "description": description
            }
        }

        always {
            ent:orders := ent:orders.put(id, new_order);

            raise order event "request_bids" attributes {"id": id}
        }
    }

    // Sends a request for bids to a driver that this store knows
    rule request_bids {
        select when order request_bids
        pre {
            id = event:attr("id")
            order = order_by_id(id).klog("Order to request bids for:")
            driver = get_driver()
        }

        if not driver.isnull() then
            event:send(
            { "eci": driver{"Tx"}, "eid": "request_bids",
                "domain": "order", "type": "needDriver",
                "attrs": { "order": order, "storeEci": meta:eci} } )

        fired {
            // Schedule an event in the future to choose a driver
            schedule order event "chooseBid" at time:add(time:now(), {"seconds": ent:bidWindowTime})
                attributes {"id": id}
        }
    }

    // Event that a driver sends to a store when it wants to bid on the order.
    rule collect_bid {
        select when order bidOnOrder
        pre {
            bid = event:attr("bid")
            eci = bid{"driverEci"}
            id = bid{"id"}
            order_already_assigned = not order_by_id(id){"assigned_driver"}.isnull()
        }

        if order_already_assigned then 
            event:send(
            { "eci": eci, "eid": "reject_bid",
                "domain": "order", "type": "rejected",
                "attrs": { "id": id} } )

        notfired {
            ent:bids := ent:bids.append(bid)
        }
    }

    rule choose_bid {
        select when order chooseBid
        pre {
            orderId = event:attr("id")
            chosen_bid = chooseBidForOrder(orderId).klog("Chosen bid:")
        }

        if not chosen_bid.isnull() then noop()

        fired {
            raise order event "acceptForOrder" attributes {"bid": chosen_bid};
            raise order event "rejectForOrder" attributes {"bid": chosen_bid};
            ent:orders := ent:orders.put([orderId, "assigned_driver"], chosen_bid{"driverEci"});
        }

        else {
            // No bids yet, so reschedule
            schedule order event "chooseBid" at time:add(time:now(), {"seconds": ent:bidWindowTime})
                attributes event:attrs()
        }
    }

    rule bid_reject {
        select when order acceptForOrder
        foreach getRejectedBids(event:attr("bid")) setting(rejected)
        
        event:send(
            { "eci": rejected{"driverEci"}, "eid": "reject_bid",
                "domain": "order", "type": "rejected",
                "attrs": { "id": rejected{"id"}} } )
    }

    rule bid_accept {
        select when order rejectForOrder
        pre {
            accepted = event:attr("bid")
        }

        event:send(
            { "eci": accepted{"driverEci"}, "eid": "accept_bid",
                "domain": "order", "type": "assigned",
                "attrs": { "id": accepted{"id"}} } )
    }

    rule order_delivered {
        select when order delivered 
        pre {
            orderId = event:attr("id")
        }

        // TODO: Send a text to person who placed order

        always {
            ent:orders := ent:orders.put([orderId, "delivered_at"], time:now());
        }
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
            attributes = event:attrs.klog("subcription:")
        }
        always {
            raise wrangler event "pending_subscription_approval"
            attributes attributes
        }
    }
}