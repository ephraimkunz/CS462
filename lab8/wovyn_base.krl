ruleset wovyn_base {
  meta {
    use module io.picolabs.subscription alias Subscriptions
    use module temperature_store
    use module sensor_profile
    shares __testing
  }
  global {
    __testing = { "queries": [ { "name": "__testing" } ],
                  "events": [ { "domain": "wovyn", "type": "heartbeat",
                              "attrs": [ "genericThing" ] } ] }

  }

  rule start_gen_report {
      select when report sensor_gen_report
      pre {
          temps = temperature_store:temperatures()
      }
       event:send(
            { "eci": event:attr("Rx"), "eid": "reportDone",
            "domain": "report", "type": "sensor_gen_report_finished",
            "attrs": {"temps": temps, "Tx": event:attr("Tx"), "corrId": event:attr("corrId")} }
        )
  }

  rule threshold_notification {
      select when wovyn threshold_violation
      foreach Subscriptions:established("Rx_role","temp_sensor_controller") setting (subscription)
        pre {
            thing_subs = subscription.klog("subs")
        }
        event:send(
            { "eci": subscription{"Tx"}, "eid": "threshold-violation",
                "domain": "sensor_manager", "type": "sub_threshold_violation",
                "attrs": event:attrs }
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

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        fired {
            raise wrangler event "pending_subscription_approval"
            attributes event:attrs
        }
    }
}