ruleset gossip_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, list_schedule, set_period
    }

    global {
        __testing = { "queries": [ { "name": "__testing" }, {"name": "list_schedule"}],
                        "events": [ { "domain": "gossip", "type": "set_period",
                                    "attrs": [ "period" ] } ] }

        list_schedule = function() {
            schedule:list()
        }

        getPeer = function() {
            // For now, just choose a peer at random
            subs = Subscriptions:established("Rx_role","node");
            rand = random:integer(subs.length());
            subs[rand]
        }

        getSeenMessage = function() {
            {"ABCD-1234-ABCD-1234-ABCD-125A": 3,
            "ABCD-1234-ABCD-1234-ABCD-129B": 5,
            "ABCD-1234-ABCD-1234-ABCD-123C": 10,
            "type": "seen"
            }
        }

        getRumorMessage = function() {
            {"MessageID": "ABCD-1234-ABCD-1234-ABCD-1234:5",
            "SensorID": "BCDA-9876-BCDA-9876-BCDA-9876",
            "Temperature": "78",
            "Timestamp": "the time stamp",
            "type": "rumor"
            }
        }

        prepareMessage = function() {
            // Choose message type
            rand = random:integer(1);
            message = (rand == 0) => getSeenMessage() | getRumorMessage();
            message
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added

        always {
            ent:period := 5;
            raise gossip event "heartbeat" attributes {"period": ent:period}
        }
    }

    rule gossip_heartbeat_reschedule {
        select when gossip heartbeat
        pre {
            period = event:attr("period")
        }

         always {
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": period}) 
                attributes {"period": ent:period}
         }
    }

    rule set_gossip_period {
        select when gossip set_period
        pre {
            period = event:attr("period").defaultsTo(ent:period)
        }

        always {
            ent:period := period
        }
    }

    rule gossip_heartbeat_process {
        select when gossip heartbeat
        pre {
            subscriber = getPeer()
            m = prepareMessage()
        }

        if not subscriber.isnull() then 
            event:send(
                { "eci": subscriber{"Tx"}, "eid": "message",
                    "domain": "gossip", "type": m{"type"},
                    "attrs": {"message": m} }
            )
    }

    rule gossip_rumor {
        select when gossip rumor
        pre {
            message = event:attr("message").klog("Gossip rumor: ")
        }
    }

    rule gossip_seen {
        select when gossip seen
        pre {
            message = event:attr("message").klog("Gossip seen: ")
        }
    }

    rule gossip_process {
        select when gossip process
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        fired {
            raise wrangler event "pending_subscription_approval"
            attributes event:attrs
        }
    }
}

