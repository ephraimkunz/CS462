ruleset mischief.owner {
  meta {
    name "mischief owner"
    description <<
      A bit of whimsy,
      inspired by Dr. Seuss's
      "The Cat in the Hat"
    >>
    author "Picolabs"
    use module io.picolabs.wrangler alias wrangler
    shares __testing
  }
  global {
    __testing = { "queries": [ { "name": "__testing" } ],
                  "events": [ { "domain": "mischief", "type": "subscriptions"} ] }
  }
  rule mischief_who {
    select when mischief who
    pre {
      mischief = event:attr("eci")
      things = wrangler:children().map(function(v){v{"eci"}})
                                  .filter(function(v){v != mischief})
    }
    always {
      ent:mischief := mischief;
      ent:things := things
    }
  }
  rule mischief_subscriptions {
    select when mischief subscriptions
    foreach ent:things setting(thing,index)
      // introduce mischief pico to thing[index] pico
      event:send(
        { "eci": ent:mischief, "eid": "subscription",
          "domain": "wrangler", "type": "subscription",
          "attrs": { "name": "thing" + (index+1),
                     "Rx_role": "controller",
                     "Tx_role": "thing",
                     "channel_type": "subscription",
                     "wellKnown_Tx": thing } } )
  }
}