ruleset store_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, get_orders, get_bids
    }

    global {
        __testing = {"events": [
            {
                "domain": "order", "type": "new", "attrs": ["phone", "description"]
            }],

            "queries": [
                {"name": "get_orders"}, {"name": "get_bids"}
            ]
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

        get_orders = function() {
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
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:bids := [];
            ent:orders := {};
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
            schedule order event "chooseBid" at time:add(time:now(), {"seconds": 10})
                attributes {"id": id}
        }
    }

    // Event that a driver sends to a store when it wants to bid on the order.
    rule collect_bid {
        select when order bidOnOrder
        pre {
            bid = event:attr("bid")
            chan = bid{"driverEci"}
            id = bid{"id"}
            order_already_assigned = not order_by_id(id){"assigned_driver"}.isnull()
        }

        if order_already_assigned then 
            event:send(
            { "eci": chan, "eid": "collect_bid",
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
            // TODO: Notify all orders for this id of accepted or rejected.
            ent:orders := ent:orders.put([orderId, "assigned_driver"], chosen_bid{"driverEci"});
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