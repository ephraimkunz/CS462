ruleset mischief {
  meta {
    name "mischief"
    description <<
      A bit of whimsy,
      inspired by Dr. Seuss's
      "The Cat in the Hat"
    >>
    author "Picolabs"
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias Subscriptions
    shares __testing
  }
  global {
    __testing = { "queries": [ { "name": "__testing" } ],
                  "events": [ { "domain": "mischief", "type": "identity"},
                              { "domain": "mischief", "type": "hat_lifted"} ] }
  }
  rule mischief_identity {
    select when mischief identity
    event:send(
      { "eci": wrangler:parent_eci(), "eid": "mischief-identity",
        "domain": "mischief", "type": "who",
        "attrs": { "eci": wrangler:myself(){"eci"} } } )
  }
  rule mischief_hat_lifted {
    select when mischief hat_lifted
    foreach Subscriptions:established("Tx_role","thing") setting (subscription)
      pre {
        thing_subs = subscription.klog("subs")
      }
      event:send(
        { "eci": subscription{"Tx"}, "eid": "hat-lifted",
          "domain": "mischief", "type": "hat_lifted" }
      )
  }
}