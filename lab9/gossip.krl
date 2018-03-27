ruleset gossip_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, set_period, list_scheduled, getMissingMessages, listTemps
    }

    global {
        __testing = { "queries": [ { "name": "__testing" }, {"name": "list_scheduled"}, {"name": "listTemps"}],
                        "events": [ { "domain": "gossip", "type": "set_period","attrs": [ "period" ] },
                        { "domain": "gossip", "type": "new_message","attrs": [  ] }  ] }
                        
        list_scheduled = function() {
            schedule:list()
        }

        listTemps = function() {
            ent:seenMessages.filter(function(a) {
                uniqueId = a{"MessageID"};
                sn = getSequenceNum(uniqueId);
                pn = getPicoId(uniqueId);

                ent:seen{pn} == sn
            });
        }

        getPeer = function() {
            // TODO: Be smart about choosing peer.
            // For now, just choose a peer at random
            subs = Subscriptions:established("Rx_role","node");
            rand = random:integer(subs.length() - 1);
            subs[rand]
        }

        // Highest consecutive sequence number for picoId received
        slideWindow = function(picoId) {
            filtered = ent:seenMessages.filter(function(a) {
                id = getPicoId(a{"MessageID"});
                id == picoId
            }).map(function(a){getSequenceNum(a{"MessageID"})});

            sorted = filtered.sort(function(a_seq, b_seq){
                a_seq < b_seq  => -1 |
                a_seq == b_seq =>  0 |
                1
            });
        
            sorted.reduce(function(a_seq, b_seq) {
                b_seq == a_seq + 1 => b_seq | a_seq
            }, -1);
        }

        getUniqueId = function() {
            sequenceNumber = ent:sequence;
            <<#{meta:picoId}:#{sequenceNumber}>>
        }

        getSeenMessage = function() {
            {
                "message": ent:seen,
                "type": "seen"
            }
        }

        getSequenceNum = function(id) {
            splitted = id.split(re#:#);
            splitted[splitted.length() - 1].as("Number")
        }

        getPicoId = function(id) {
            splitted = id.split(re#:#);
            splitted[0]
        }

        getMissingMessages = function(seen) {
            ent:seenMessages.filter(function(a) {
                id = getPicoId(a{"MessageID"});
                keep = id.isnull() || (seen{id}.klog("Seen id:") < getSequenceNum(a{"MessageID"}).klog("Sequence num:")) => true | false;
                keep
            })
        }

        getRumorMessage = function() {
            // TODO: Use intelligence to decide which message to send.
            rand = random:integer(ent:seenMessages.length() - 1);
            msg = {
                "message": ent:seenMessages.length() == 0 => null | ent:seenMessages[rand],
                "type": "rumor"
            };
            msg
        }

        prepareMessage = function() {
            // Choose message type
            rand = random:integer(1);
            message = (rand == 0) => getSeenMessage() | getRumorMessage();
            message
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:period := 5;
            ent:sequence := 0;
            ent:counter := -1;
            ent:seen := {};
            ent:peerState := {};
            ent:seenMessages := [];
            raise gossip event "heartbeat" attributes {"period": ent:period}
        }
    }

    rule gossip_heartbeat_reschedule {
        select when gossip heartbeat
        pre {
            period = ent:period
        }

         always {
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": period})
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

        if (not subscriber.isnull()) && (not m{"message"}.klog("Message:").isnull()) then 
            noop()
        fired {
            raise gossip event "send_rumor" 
                attributes {"subscriber": subscriber, "message": m{"message"}}
            if (m{"type"} == "rumor");

            raise gossip event "send_seen"
                attributes {"subscriber": subscriber, "message": m{"message"}} 
            if (m{"type"} == "seen");
        }
    }

    rule gossip_send_seen {
        select when gossip send_seen
        pre {
            sub = event:attr("subscriber")
            mess = event:attr("message")
        }

        event:send(
            { "eci": sub{"Tx"}, "eid": "gossip_message",
                "domain": "gossip", "type": "seen",
                "attrs": {"message": mess, "sender": {"picoId": meta:picoId, "Rx": sub{"Rx"}}}
            }
        )
    }

    rule gossip_send_rumor {
        select when gossip send_rumor
        pre {
            sub = event:attr("subscriber")
            mess = event:attr("message")
        }

        event:send(
            { "eci": sub{"Tx"}, "eid": "gossip_message",
                "domain": "gossip", "type": "rumor",
                "attrs": mess
            }
        )

        always {
            // TODO: Increment sequence number if necessary

        }
    }

    // Store rumor and create highest sequential seen entry if necessary.
    rule gossip_rumor {
        select when gossip rumor
        pre {
            id = event:attr("MessageID")
            seq_num = getSequenceNum(id)
            pico_id = getPicoId(id)
            seen = ent:seen{pico_id}
            first_seen = ent:seen{pico_id}.isnull()
        }

        if first_seen then
            noop()
        
        fired {
            ent:seen := ent:seen.put(pico_id, -1)
        } finally {
            ent:seenMessages := ent:seenMessages.append({
                "MessageID": id,
                "SensorID": event:attr("SensorID"),
                "Temperature": event:attr("Temperature"),
                "Timestamp": event:attr("Timestamp")}) 
            if ent:seenMessages.filter(function(a) {a{"MessageID"} == id}).length() == 0;

            raise gossip event "update_sequential_seen"
                attributes {"picoId": pico_id, "seqNum": seq_num}
        }
    }

    rule update_sequential_seen {
        select when gossip update_sequential_seen
        pre {
            pico_id = event:attr("picoId")
            seq_num = event:attr("seqNum").as("Number")
        }

        always {
            ent:seen := ent:seen.put(pico_id, slideWindow(pico_id))
        }
    }

    rule gossip_seen_save {
        select when gossip seen
        pre {
            senderId = event:attr("sender"){"picoId"}
            message = event:attr("message")
        }

        always {
            ent:peerState := ent:peerState.put(senderId, message)
        }
    }

    rule gossip_seen_return_missing {
        select when gossip seen
        foreach getMissingMessages(event:attr("message")).klog("Missing:") setting(mess)
        pre {
            senderId = event:attr("sender"){"picoId"}
            rx = event:attr("sender"){"Rx"}
        }

        event:send(
            { "eci": rx, "eid": "gossip_message_response",
                "domain": "gossip", "type": "rumor",
                "attrs": mess
            }
        )
    }

    rule gossip_process {
        select when gossip process
    }

    rule gossip_new_message {
        select when gossip new_message 
        always {
            ent:counter := ent:counter + 1;
            ent:seenMessages := ent:seenMessages.defaultsTo([]).append({"MessageID":<<#{meta:picoId}:#{ent:counter}>>,"SensorID":"BCDA-9876-BCDA-9876-BCDA-9876","Temperature":"78","Timestamp":"the time stamp"})
        }
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        fired {
            raise wrangler event "pending_subscription_approval"
            attributes event:attrs
        }
    }
}

