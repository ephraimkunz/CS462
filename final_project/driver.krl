ruleset driver_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, getQueue, getPendingOrder, getCompletedOrders, getRating
    }
    
    global {
        __testing = {"events": [
            {"domain": "driver", "type": "changeRating", "attrs": ["rating"]}
        ],

            "queries": [
                {"name": "getQueue"}, {"name": "getPendingOrder"}, {"name": "getCompletedOrders"}, {"name": "getRating"}
            ]
        }

        getQueue = function() {
            ent:queuedForBid
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

        // Override point for additional conditions on whether we will choose to bid.
        shouldBidOnOrder = function(order) {
            true
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:pendingBid := null;
            ent:completedDelivery := [];
            ent:queuedForBid := [];
            ent:rating := 4.5;
        }
    }

    // Enqueue new request
    rule order_need_driver {
        select when order needDriver
        pre {
            storeEci = event:attr("storeEci")
            order = event:attr("order")

            // TODO: Determine if I want to submit a bid
            // TODO: Gossip order to neighbors
            bid = {
                "id": order{"id"},
                "dist": 5,
                "rating": ent:rating,
                "driverEci": meta:eci,
                "storeEci": storeEci
            }
        }

        always {
            // Store as pending bid. Can only have one pending bid at a time (in case it is accepted).
            ent:queuedForBid := ent:queuedForBid.append(bid);
            raise order event "tryAnotherBid" if ent:pendingBid.isnull();
        }
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
            // TODO: Randomly choose time
            schedule order event "justDelivered" at time:add(time:now(), {"seconds": 10})
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
            newRating = event:attr("rating").defaultsTo(ent:rating)
        }

        always {
            ent:rating := newRating;
        }
    }
}