ruleset store_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        use module com.ephraimkunz.api_keys
        use module twilio_v2_api alias twilio
            with account_sid = keys:twilio{"account_sid"}
            auth_token =  keys:twilio{"auth_token"}
        use module distance alias dist
            with auth_token = keys:distance{"auth_token"}

        shares __testing, get_all_orders, get_bids, get_assigned_orders, get_completed_orders, getLocation
    }

    global {
        __testing = {"events": [
            {
                "domain": "order", "type": "new", "attrs": ["phone", "description"]
            },
            {
                "domain": "store", "type": "setLocation", "attrs": ["latitude", "longitude"]
            }],

            "queries": [
                {"name": "get_all_orders"}, {"name": "get_bids"}, {"name": "get_assigned_orders"}, {"name": "get_completed_orders"}, {"name": "getLocation"}
            ]
        }

        getLocation = function() {
            ent:location
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

        getDistance = function(alat, alon, blat, blon) {
            output = dist:get_distance(alat,alon,blat,blon).klog("Store dist calculated:");
            output;
        }

        chooseBidForOrder = function(orderId) {
            filtered = ent:bids.filter(function(a){a{"id"} == orderId}).klog("Filtered:");

            sorted = filtered.sort(function(a, b) {
                alat = a{["driverLocation", "latitude"]};
                alon = a{["driverLocation", "longitude"]};
                blat = b{["driverLocation", "latitude"]};
                blon = b{["driverLocation", "longitude"]};
                storelat = ent:location{"latitude"};
                storelon = ent:location{"longitude"};

                a{"rating"} > b{"rating"}  => -1 |
                a{"rating"} == b{"rating"} && (getDistance(alat, alon, storelat, storelon) < getDistance(blat, blon, storelat, storelon)) =>  -1 | 1
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
            ent:storePhoneNumber := "+14352653308";
            ent:location := {"latitude": "40.2968979", "longitude": "-111.69464749999997"};
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
                "attrs": { "order": order, "storeEci": meta:eci, "storeLocation": ent:location} } )

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
            order = order_by_id(orderId)
            chosen_bid = chooseBidForOrder(orderId).klog("Chosen bid:")
        }

        if not chosen_bid.isnull() then noop()

        fired {
            raise order event "acceptForOrder" attributes {"bid": chosen_bid};
            raise order event "rejectForOrder" attributes {"bid": chosen_bid};
            ent:orders := ent:orders.put([orderId, "assigned_driver"], chosen_bid{"driverEci"});
            raise customer event "sendMessage" attributes 
                {
                    "phoneNumber": order{"customer_phone"},
                    "message": "Order with description " + order{"description"} + " was accepted by " + chosen_bid{"driverEci"} + " at " + time:now()
                }
        }

        else {
            // No bids yet, so reschedule
            schedule order event "chooseBid" at time:add(time:now(), {"seconds": ent:bidWindowTime})
                attributes event:attrs
        }
    }

    rule bid_reject {
        select when order rejectForOrder
        foreach getRejectedBids(event:attr("bid")) setting(rejected)
        
        event:send(
            { "eci": rejected{"driverEci"}, "eid": "reject_bid",
                "domain": "order", "type": "rejected",
                "attrs": { "id": rejected{"id"}} } )
    }

    rule bid_accept {
        select when order acceptForOrder
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
            order = order_by_id(orderId)
            delivered_at = time:now()
        }

        always {
            ent:orders := ent:orders.put([orderId, "delivered_at"], delivered_at);
            raise customer event "sendMessage" attributes 
                {
                    "phoneNumber": order{"customer_phone"},
                    "message": "Order with description " + order{"description"} + " was delivered by " + order{"assigned_driver"} + " at " + delivered_at
                }
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

    rule update_customer_via_text {
        select when customer sendMessage
        pre {
            message = event:attr("message")
            toNumber = event:attr("phoneNumber")
        }

        twilio:send_sms(toNumber,
                            ent:storePhoneNumber,
                            message)
    }

    rule set_location {
        select when store setLocation
        pre {
            lat = event:attr("latitude").defaultsTo(ent:location{"latitude"})
            lon = event:attr("longitude").defaultsTo(ent:location{"longitude"})
        }

        always {
            ent:location := {"latitude": lat, "longitude": lon}
        }
    }
}