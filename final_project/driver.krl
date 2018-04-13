ruleset driver_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        use module com.ephraimkunz.api_keys
        use module distance alias dist with auth_token = keys:distance{"auth_token"}
        shares __testing, getQueue, getPendingOrder, getCompletedOrders, getRating, getLocation
    }
    
    global {
        __testing = {"events": [
            {"domain": "driver", "type": "changeRating", "attrs": ["rating"]},
            {"domain": "driver", "type": "setLocation", "attrs": ["latitude", "longitude"]}
        ],

            "queries": [
                {"name": "getQueue"}, {"name": "getPendingOrder"}, {"name": "getCompletedOrders"}, {"name": "getRating"}, {"name": "getLocation"}
            ]
        }

        getLocation = function() {
            ent:location
        }

        getQueue = function() {
            ent:queuedForBid
        }

        getDriverPeers = function() {
            subs = Subscriptions:established("Rx_role","driver").klog("Peers:");
            subs
        }

        getRating = function() {
            ent:rating
        }

        getPendingOrder = function() {
            ent:pendingBid
        }

        getCompletedOrders = function() {
            ent:completedDelivery
        }

        getNextFromQueuedForBid = function() {
            ent:queuedForBid.length() == 0 => null | ent:queuedForBid[0];
        }

        getDistance = function(alat, alon, blat, blon) {
            output = dist:get_distance(alat,alon,blat,blon).klog("Driver dist calculated:");
            output;
        }

        // Override point for additional conditions on whether we will choose to bid.
        shouldBidOnOrder = function(order) {
            // Only bid if store is close enough
            driverLat = ent:location{"latitude"};
            driverLon = ent:location{"longitude"};
            storeLat = order{["storeLocation", "latitude"]};
            storeLon = order{["storeLocation", "longitude"]};

            getDistance(driverLat, driverLon, storeLat, storeLon) < ent:maxDistanceForBidding
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:pendingBid := null;
            ent:completedDelivery := [];
            ent:queuedForBid := [];
            ent:rating := random:integer(5);
            ent:location := {"latitude": "40.24893579577157", "longitude": "-111.64955822289846"};
            ent:forwardedOrderIds := []; // All order id's I've seen / forwarded. Each driver forwards each id exactly once.
            ent:maxDistanceForBidding := 10000;
        }
    }

    // Enqueue new request
    rule order_need_driver {
        select when order needDriver where (not (ent:forwardedOrderIds >< event:attr("order"){"id"})).klog("Not forwarded yet?:")
        pre {
            storeEci = event:attr("storeEci")
            order = event:attr("order")
            storeLocation = event:attr("storeLocation")

            bid = {
                "id": order{"id"},
                "driverLocation": ent:location,
                "rating": ent:rating,
                "driverEci": meta:eci,
                "storeEci": storeEci,
                "storeLocation": storeLocation
            }
        }

        always {
            // Store as pending bid. Can only have one pending bid at a time (in case it is accepted).
            ent:queuedForBid := ent:queuedForBid.append(bid);
            raise order event "tryAnotherBid" if ent:pendingBid.isnull();

            // Gossip to neighbors
            raise order event "forward" attributes event:attrs;
            ent:forwardedOrderIds := ent:forwardedOrderIds.append(order{"id"})
        }
    }

    rule forward_order {
        select when order forward
        foreach getDriverPeers() setting(driver)
        
        event:send({ "eci": driver{"Tx"}, "eid": "request_bids_forwarded",
                "domain": "order", "type": "needDriver",
                "attrs": event:attrs})
    }

    rule try_another_bid {
        select when order tryAnotherBid
        pre {
            // Take first item off of queue. Send a bid if I want. Advance queue in any case.
            next = getNextFromQueuedForBid().klog("Next:")
            next_valid = not next.isnull()
        }

        if next_valid && shouldBidOnOrder(next) then 
            event:send(
            { "eci": next{"storeEci"}, "eid": "offer_bid",
                "domain": "order", "type": "bidOnOrder",
                "attrs": { "bid": next }} )

        always {
            ent:queuedForBid := ent:queuedForBid.slice(1, ent:queuedForBid.length() - 1) if next_valid;

            // Add to pendingBid
            ent:pendingBid := next if next_valid && shouldBidOnOrder(next);
        }
    }

    // Pending bid rejected, try another bid on the list
    rule bid_rejected {
        select when order rejected

        always {
            ent:pendingBid := null;
            raise order event "tryAnotherBid";
        }
    }

    // Pending bid accepted, now go and deliver
    rule bid_accepted {
        select when order assigned
        always {
            schedule order event "justDelivered" at time:add(time:now(), {"seconds": random:integer(upper = 60, lower = 30)})
        }
    }

    // Notify the store when I've finished delivering the order
    rule just_delivered_order {
        select when order justDelivered
        
        event:send(
            { "eci": ent:pendingBid{"storeEci"}, "eid": "delivered_order",
                "domain": "order", "type": "delivered",
                "attrs": { "id": ent:pendingBid{"id"} }} )

        always {
            // Delivered now, so no more pending
            ent:completedDelivery := ent:completedDelivery.append(ent:pendingBid);
            ent:pendingBid := null;
            raise order event "tryAnotherBid";
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

    rule change_rating {
        select when driver changeRating
        pre {
            newRating = event:attr("rating").as("Number").defaultsTo(ent:rating)
        }

        always {
            ent:rating := newRating;
        }
    }

    rule set_location {
        select when driver setLocation
        pre {
            lat = event:attr("latitude").defaultsTo(ent:location{"latitude"})
            lon = event:attr("longitude").defaultsTo(ent:location{"longitude"})
        }

        always {
            ent:location := {"latitude": lat, "longitude": lon}
        }
    }
}