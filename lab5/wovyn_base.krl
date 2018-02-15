ruleset wovyn_base {
  meta {
    use module com.ephraimkunz.api_keys
    use module twilio_v2_api alias twilio
        with account_sid = keys:twilio("account_sid")
        auth_token =  keys:twilio("auth_token")
    use module sensor_profile
    shares __testing
  }
  global {
    __testing = { "queries": [ { "name": "__testing" } ],
                  "events": [ { "domain": "wovyn", "type": "heartbeat",
                              "attrs": [ "genericThing" ] } ] }

    from_number = "+14352653308"
  }

  rule threshold_notification {
      select when wovyn threshold_violation
      twilio:send_sms(sensor_profile:get_profile(){"number"},
                        from_number,
                        "Temp violation: " + event:attr("temperature") + " on " + event:attr("timestamp")
                        )
  }

  rule find_high_temps {
      select when wovyn new_temperature_reading
      pre {
          temp = event:attr("temperature")
          threshold = sensor_profile:get_profile(){"high"}.as("Number")
          violation = (temp > threshold)
      }

      if violation then
        send_directive("temp_violation", {"occurred": violation})

      fired {
          raise wovyn event "threshold_violation"
            attributes event:attrs
      }
  }
 
  rule process_heartbeat {
    select when wovyn heartbeat where genericThing
    pre {
        temp = event:attr("genericThing"){"data"}{"temperature"}[0]{"temperatureF"}
        timestamp = time:now()
    }

    send_directive("heartbeat", {"data": temp})

    fired {
        raise wovyn event "new_temperature_reading"
            attributes {"temperature": temp, "timestamp": timestamp}
    }
  }
}