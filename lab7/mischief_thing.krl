ruleset mischief.thing {
  meta {
    name "mischief.thing"
    description <<
      A bit of whimsy,
      inspired by Dr. Seuss's
      "The Cat in the Hat"
    >>
    author "Picolabs"
    shares __testing, status
  }
  global {
    __testing = { "queries": [ { "name": "__testing" },
                               { "name": "status" } ],
                  "events": [ { "domain": "mischief", "type": "mom_home" } ] }
    status = function() {
      ent:status.defaultsTo("inactive") + " level " + ent:serial.defaultsTo(0)
    }
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
  rule mischief_hat_lifted {
    select when mischief hat_lifted
    fired {
      ent:status := "active";
      ent:serial := ent:serial.defaultsTo(0) + 1
    }
  }
  rule mischief_mom_coming_home {
    select when mischief mom_home
    fired {
      ent:status := "inactive";
    }
  }
}