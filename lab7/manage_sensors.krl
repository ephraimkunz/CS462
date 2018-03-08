ruleset manage_sensors {
    meta {
        shares __testing, sensors, getAllTemps
        use module io.picolabs.subscription alias Subscriptions
        use module management_profile
    }
    global {
        sensors = function() {
            Subscriptions:established("Rx_role", "temp_sensor")
        }

        cloud_url = "http://localhost:8080/sky/cloud/";

        getTemp = function(v, k) {
            eci = v{"Tx"};
            url = cloud_url + eci + "/temperature_store/temperatures";
            response = http:get(url);
            response{"content"}.decode();
        }

        getAllTemps = function() {
            sensors().map(getTemp)
        }

        __testing = { "queries": [ { "name": "__testing" }, {"name": "sensors"}, {"name": "getAllTemps"} ],
                        "events": [ { "domain": "sensor", "type": "new_sensor",
                                    "attrs": [ "name" ] },
                                    {"domain": "sensor", "type": "introduce", "attrs": ["name", "eci", "host"]},
                                    {"domain": "collection", "type": "empty",
                                    "attrs": []},
                                    {"domain": "sensor", "type": "unneeded_sensor", 
                                    "attrs": ["name"]} ] }
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

    rule sub_added {
        select when wrangler subscription_added
        pre {
            Tx = event:attr("_Tx").klog("_Tx: ")
        }
        always {

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