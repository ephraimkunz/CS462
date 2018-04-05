ruleset gossip_ruleset {
    meta {
        use module io.picolabs.subscription alias Subscriptions
        shares __testing, set_period, list_scheduled, getMissingMessages, listTemps, getProcess
    }

    global {
        __testing = { "queries": [ { "name": "__testing" }, {"name": "list_scheduled"}, {"name": "listTemps"}, {"name": "getProcess"}],
                        "events": [ { "domain": "gossip", "type": "set_period","attrs": [ "period" ] },
                        { "domain": "gossip", "type": "process","attrs": [ "status" ] } ] }
                        
        list_scheduled = function() {
            schedule:list()
        }

        getProcess = function() {
            ent:process
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
            // Choose a peer randomly from the subset that need something.
            subs = Subscriptions:established("Rx_role","node").klog("Subs:");
            rand_sub = random:integer(subs.length() - 1); // Only used if filtered is empty
            
            peers = ent:peerState;
            filtered = peers.filter(function(v,k){
                getMissingMessages(v).length() > 0;
            }).klog("Filtered:");

            rand = random:integer(filtered.length() - 1).klog("Rand:");
            item = filtered.keys()[rand].klog("item:");
            subs.filter(function(a){a{"Tx"} == item})[0].klog("Final:").isnull() => subs[rand_sub] | subs.filter(function(a){a{"Tx"} == item})[0]
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

        createNewMessage = function(temp, time) {
            {
                "MessageID": getUniqueId(),
                "SensorID": meta:picoId,
                "Temperature": temp,
                "Timestamp": time
            }
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
                keep = seen{id}.isnull() || (seen{id} < getSequenceNum(a{"MessageID"})) => true | false;
                keep
            }).sort(function(a, b) {
                a_seq = getSequenceNum(a{"MessageID"});
                b_seq = getSequenceNum(b{"MessageID"});
                a_seq < b_seq  => -1 |
                a_seq == b_seq =>  0 |
                1
            });
        }

        getRumorMessage = function(subscriber) {
            missing = getMissingMessages(ent:peerState{subscriber{"Tx"}}).klog("Missing messages:");
            msg = {
                "message": missing.length() == 0 => null | missing[0],
                "type": "rumor"
            };
            msg
        }

        prepareMessage = function(subscriber) {
            // Choose message type
            rand = random:integer(1);
            message = (rand == 0) => getSeenMessage() | getRumorMessage(subscriber);
            message
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where rids >< meta:rid

        always {
            ent:period := 3;
            ent:sequence := 0;
            ent:seen := {};
            ent:peerState := {};
            ent:seenMessages := [];
            ent:process := "on";
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
        select when gossip heartbeat where ent:process == "on"
        pre {
            subscriber = getPeer().klog("Chosen to send to:")
            m = prepareMessage(subscriber)
        }

        if (not subscriber.isnull()) && (not m{"message"}.isnull()) then 
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
            mess_picoId = getPicoId(mess{"MessageID"})
            mess_seqNum = getSequenceNum(mess{"MessageID"})
        }

        event:send(
            { "eci": sub{"Tx"}, "eid": "gossip_message",
                "domain": "gossip", "type": "rumor",
                "attrs": mess
            }
        )

        always {
            // Update our view of our peers
            ent:peerState := ent:peerState.put([sub{"Tx"}, mess_picoId], mess_seqNum)
            if (ent:peerState{sub{"Tx"}}{mess_picoId} + 1 == mess_seqNum) || (ent:peerState{sub{"Tx"}}{mess_picoId}.isnull() && mess_seqNum == 0);
        }
    }

    // Store rumor and create highest sequential seen entry if necessary.
    rule gossip_rumor {
        select when gossip rumor where ent:process == "on"
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
        select when gossip seen where ent:process == "on"
        pre {
            senderChan = event:attr("sender"){"Rx"}
            message = event:attr("message")
        }

        always {
            // Store peers by channel so we can reconcile with subscription list.
            ent:peerState := ent:peerState.put(senderChan, message)
        }
    }

    rule gossip_seen_return_missing {
        select when gossip seen where ent:process == "on"
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
        pre {
            status = event:attr("status")
        }

        always {
            ent:process := status;
        }
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
            Tx = event:attr("Tx").klog("Tx: ")
        }
        if not Tx.isnull() then noop()
        fired {
            raise wrangler event "pending_subscription_approval"
            attributes event:attrs;

            ent:peerState := ent:peerState.put(Tx, {})
        }
    }

    rule sub_added {
        select when wrangler subscription_added
        pre {
            Tx = event:attr("_Tx").klog("_Tx: ")
        }
        if not Tx.isnull() then noop()
        fired {
            ent:peerState := ent:peerState.put(Tx, {})
        }
    }

    rule new_temp_from_sensor {
        select when wovyn new_temperature_reading
        pre {
            temp = event:attr("temperature")
            time = event:attr("timestamp")
            msg = createNewMessage(temp, time)
        }
        always {
            ent:seenMessages := ent:seenMessages.append(msg);
            ent:seen := ent:seen.put(meta:picoId, slideWindow(meta:picoId));
            ent:sequence := ent:sequence + 1;
        }
    }
}

