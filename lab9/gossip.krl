ruleset gossip_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, list_schedule, set_period
    }

    global {
        __testing = { "queries": [ { "name": "__testing" }, {"name": "list_schedule"}],
                        "events": [ { "domain": "gossip", "type": "set_period","attrs": [ "period" ] } ] }

        list_schedule = function() {
            schedule:list()
        }

        getPeer = function() {
            // For now, just choose a peer at random
            subs = Subscriptions:established("Rx_role","node");
            rand = random:integer(subs.length() - 1).klog("Random peer");
            subs[rand]
        }

        getUniqueId = function() {
            sequenceNumber = ent:sequence.defaultsTo(0);
            <<#{meta:picoId}:#{sequenceNumber}>>
        }

        getSeenMessage = function() {
            {"ABCD-1234-ABCD-1234-ABCD-125A": 3,
            "ABCD-1234-ABCD-1234-ABCD-129B": 1,
            "ABCD-1234-ABCD-1234-ABCD-123C": 10,
            "type": "seen",
            "id": getUniqueId()
            }
        }

        getSequenceNum = function(id) {
            splitted = id.split(re#:#);
            splitted[splitted.length() - 1]
        }

        getPicoId = function(id) {
            splitted = id.split(re#:#);
            splitted[0]
        }

        getRumorMessage = function() {
            {"MessageID": "ABCD-1234-ABCD-1234-ABCD-1234:1",
            "SensorID": "BCDA-9876-BCDA-9876-BCDA-9876",
            "Temperature": "78",
            "Timestamp": "the time stamp",
            "type": "rumor",
            "id": getUniqueId()
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
            ent:period := 10;
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
        fired {
            ent:sequence := ent:sequence.defaultsTo(0) + 1;
        }
    }

    // Store rumor and create highest sequential seen entry if necessary.
    rule gossip_rumor {
        select when gossip rumor
        pre {
            message = event:attr("message").klog("Gossip rumor: ")
            seq_num = getSequenceNum(message{"MessageID"})
            pico_id = getPicoId(message{"MessageID"})
            first_seen = ent:seen{pico_id}.isnull()
        }

        if first_seen then
            noop()
        
        fired {
            ent:seen := ent:seen.defaultsTo({}).put(pico_id, 0)
        } finally {
            ent:seenMessages := ent:seenMessages.defaultsTo([]).append(message);
            raise gossip event "update_sequential_seen"
                attributes {"picoId": pico_id, "seqNum": seq_num}
        }
    }

    rule update_sequential_seen {
        select when gossip update_sequential_seen
        pre {
            pico_id = event:attr("picoId").klog("Pico_id: ")
            seq_num = event:attr("seqNum").as("Number").klog("Sequence number: ")
        }

        if ent:seen{pico_id} + 1 == seq_num then
            noop()

        fired {
            ent:seen := ent:seen.put(pico_id, seq_num)
        }
    }

    rule gossip_seen {
        select when gossip seen
        //pre {
        //    message = event:attr("message").klog("Gossip seen: ")
        //}
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

