ruleset manage_sensors {
    meta {
        shares __testing, sensors, getReports
        use module io.picolabs.subscription alias Subscriptions
        use module management_profile
    }
    global {
        sensors = function() {
            Subscriptions:established("Rx_role", "temp_sensor")
        }

        getReports = function() {
            // Return 5 most recent reports
            reversed = ent:finishedReports.defaultsTo([]).reverse();
            len = reversed.length() > 4 => 4 | reversed.length();
            reversed.slice(len)
        }

        __testing = { "queries": [ { "name": "__testing" }, {"name": "sensors"}, {"name": "getReports"} ],
                        "events": [ { "domain": "sensor", "type": "new_sensor",
                                    "attrs": [ "name" ] },
                                    {"domain": "sensor", "type": "introduce", "attrs": ["name", "eci", "host"]},
                                    {"domain": "collection", "type": "empty",
                                    "attrs": []},
                                    {"domain": "sensor", "type": "unneeded_sensor", 
                                    "attrs": ["name"]},
                                    {"domain": "report", "type": "start", 
                                    "attrs": []} ] }
    }

    rule start_report_gen {
        select when report start
        pre {
            corrId = random:uuid()
        }
        always {
            ent:reportsInProgress := ent:reportsInProgress.defaultsTo({});
            ent:reportsInProgress := ent:reportsInProgress.put([corrId], {"temperature_sensors": sensors().length(), "temperatures": []});
            raise report event "sendStartToEachPico" attributes {"corrId": corrId}
        }
    }

    rule send_start_report_gen_to_each {
        select when report sendStartToEachPico
        foreach sensors() setting(sensor)
        pre {
            send_attrs = {"Rx": sensor{"Rx"}, "Tx": sensor{"Tx"}, "corrId": event:attr("corrId")}
        }
        event:send(
            { "eci": sensor{"Tx"}, "eid": "reportStart",
            "domain": "report", "type": "sensor_gen_report",
            "attrs": send_attrs }
        )
    }

    rule received_single_report {
        select when report sensor_gen_report_finished
        pre {
            corrId = event:attr("corrId")
            tx = event:attr("Tx")
            temps = event:attr("temps")
            report = ent:reportsInProgress{corrId}
            newReportList = report{"temperatures"}.append({"tx": tx, "temps": temps})
        }
        if (report["temperature_sensors"] == newReportList.length()) then noop()
        fired {
            // Move to finished list
            ent:reportsInProgress := ent:reportsInProgress.put([corrId], {"temperature_sensors": report["temperature_sensors"], "temperatures": newReportList});
            ent:finishedReports := ent:finishedReports.defaultsTo([]).append({
                "temperature_sensors": ent:reportsInProgress{[corrId, "temperature_sensors"]},
                "responding": ent:reportsInProgress{[corrId, "temperatures"]}.length(),
                "temperatures": ent:reportsInProgress{[corrId, "temperatures"]}
            })
        } else {
            // Add to list of respondants
            ent:reportsInProgress := ent:reportsInProgress.put([corrId], {"temperature_sensors": report["temperature_sensors"], "temperatures": newReportList});
        }
    }


    rule empty_collection {
        select when collection empty
        always {
            ent:sensors := {}
        }
    }

    rule create_new_sensor {
        select when sensor new_sensor
        pre {
            name = event:attr("name")
            exists = ent:sensors >< name
        }

        if not exists then
            noop()
        fired {
            raise wrangler event "child_creation"
                attributes {"name": name, "color": "#e06238", "rids": ["io.picolabs.subscription", "temperature_store", "sensor_profile", "wovyn_base"]}
        }
    }

    rule store_new_sensor {
        select when wrangler new_child_created
        pre {
            eci = event:attr("eci")
            sensor_name = event:attr("name")
        }

        always {
            ent:sensors := ent:sensors.defaultsTo({});
            ent:sensors{[sensor_name]} := {};
            raise wrangler event "subscription" attributes
                {
                    "name": sensor_name,
                    "Rx_role": "temp_sensor",
                    "Tx_role": "temp_sensor_controller",
                    "channel_type": "subscription",
                    "wellKnown_Tx": eci
                }
        }
    }

    rule remove_unneeded_sensor {
        select when sensor unneeded_sensor
        pre {
            name = event:attr("name")
            exists = ent:sensors >< name
            sensor = ent:sensors{name}.klog("Sensor to delete")
        }

        if exists then
            noop()
        fired {
            raise wrangler event "child_deletion"
                attributes sensor;
            ent:sensors := ent:sensors.delete([name])
        }
    }

     rule introduce_to_sensor {
        select when sensor introduce
        pre {
            eci = event:attr("eci")
            sensor_name = event:attr("name")
            host = event:attr("host")
        }

        always {
            raise wrangler event "subscription" attributes
                {
                    "name": sensor_name,
                    "Rx_role": "temp_sensor",
                    "Tx_host": host,
                    "Tx_role": "temp_sensor_controller",
                    "channel_type": "subscription",
                    "wellKnown_Tx": eci
                }
        }
    }

    rule handle_violation_from_sub {
        select when sensor_manager sub_threshold_violation
        pre {
            message = "Temp violation: " + event:attr("temperature") + " on " + event:attr("timestamp")
        }
        always{
            raise management_profile event "send_message"
                attributes {"message": message}
        }
    }
}