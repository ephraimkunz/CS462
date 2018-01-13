ruleset hello_world {
  meta {
    name "Hello World"
    description <<
A first ruleset for the Quickstart
>>
    author "Phil Windley"
    logging on
    shares hello, __testing
  }
  
  global {
    hello = function(obj) {
      msg = "Hello " + obj;
      msg
    }

    __testing = { "queries": [ { "name": "hello", "args": [ "obj" ] },
                           { "name": "__testing" } ],
              "events": [ { "domain": "echo", "type": "hello", "attrs": ["name"] } ]
            }
  }
  
  rule hello_world {
    select when echo hello
    pre {
      name = event:attr("name").klog("our passed in name: ")
    }
    send_directive("say", {"something": "Hello " + name})
  }
  
  rule hello_world_monkey {
    select when echo monkey
    pre {
      name = event:attr("name").defaultsTo("Monkey").klog("name value used: ")
    }
    send_directive("say", {"something": "Hello " + name})
  }

  rule hello_world_monkey_ternary {
    select when echo monkey2
    pre {
      name = ((event:attr("name") == null) => "Monkey" | event:attr("name")).klog("name value used: ")
    }
    send_directive("say", {"something": "Hello " + name})
  }
}
