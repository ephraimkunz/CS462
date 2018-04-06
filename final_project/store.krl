ruleset store_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, get_waiting_on_driver
    }

    global {
        __testing = {"events": [
            {
                "domain": "order", "type": "new", "attrs": ["phone", "description"]
            }],

            "queries": [
                {"name": "get_waiting_on_driver"}
            ]
        }

        get_driver = function() {
            subs = Subscriptions:established("Rx_role","driver").klog("Drivers:");
            
            // Return a random driver from this list of drivers the store knows about
            rand_sub = random:integer(subs.length() - 1);
            subs[rand_sub]
        }

        waiting_on_driver_by_id = function(id) {
            ent:waiting_on_driver.filter(function(a) {a{"id"} == id})[0]
        }

        get_waiting_on_driver = function() {
            ent:waiting_on_driver
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:waiting_on_driver := [];
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
            ent:waiting_on_driver := ent:waiting_on_driver.append(new_order);

            raise order event "request_bids" attributes {"id": id}
        }
    }

    // Sends a request for bids to a driver that this store knows
    rule request_bids {
        select when order request_bids
        pre {
            id = event:attr("id")
            order = waiting_on_driver_by_id(id).klog("Order to request bids for:")
            driver = get_driver()
        }

        if not driver.isnull() then
            event:send(
            { "eci": driver{"Tx"}, "eid": "set_profile",
                "domain": "order", "type": "needDriver",
                "attrs": { "order": order, "storeId": meta:picoId} } )
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