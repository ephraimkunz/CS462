ruleset driver_ruleset {
    rule order_need_driver {
        select when order needDriver
        pre {
            storeEci = event:attr("storeEci")
            order = event:attr("order")

            // TODO: Determine if I want to submit a bid
            // TODO: Gossip order to neighbors
            should_submit_bid = true
            bid = {
                "id": order{"id"},
                "dist": 5,
                "driverEci": meta:eci
            }
        }

        if should_submit_bid then 
            event:send(
            { "eci": storeEci, "eid": "offer_bid",
                "domain": "order", "type": "bidOnOrder",
                "attrs": { "bid": bid }} )

        fired {
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