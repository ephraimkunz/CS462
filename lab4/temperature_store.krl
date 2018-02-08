ruleset temperature_store {
    meta {
        provides temperatures, threshold_violations, inrange_temperatures
        shares __testing, temperatures, threshold_violations, inrange_temperatures
    }
    global {
         __testing = {
             "queries": [
                {"name": "temperatures", "args": []}, 
                {"name": "threshold_violations", "args": []},
                {"name": "inrange_temperatures", "args": []}],
             "events": [ 
                { "domain": "wovyn", "type": "new_temperature_reading", "attrs": [ "timestamp", "temperature" ] },
                { "domain": "wovyn", "type": "threshold_violation", "attrs": [ "timestamp", "temperature" ] },
                { "domain": "sensor", "type": "reading_reset", "attrs": [ ] } ] 
            }

        temperatures = function() {
            ent:all_temps
        }

        threshold_violations = function() {
            ent:all_violations
        }

        inrange_temperatures = function() {
            temperatures().difference(threshold_violations())
        }
     }
    rule collect_temperatures {
        select when wovyn new_temperature_reading
        pre {
            temp = event:attr("temperature")
            time = event:attr("timestamp")
        }

        always {
            ent:all_temps := ent:all_temps.defaultsTo([]); // Initialize the first time
            ent:all_temps := ent:all_temps.append({"time": time, "temp": temp})
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation
        pre {
            temp = event:attr("temperature")
            time = event:attr("timestamp")
        }

        always {
            ent:all_violations := ent:all_violations.defaultsTo([]); // Initialize the first time
            ent:all_violations := ent:all_violations.append({"time": time, "temp": temp})
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset
        always {
            ent:all_temps := [];
            ent:all_violations := [];
        }
    }
}