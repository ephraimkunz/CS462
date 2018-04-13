ruleset distance {
  meta {
    configure using auth_token = ""
    provides get_distance
  }
  global {
    get_distance = function(lat1,longe1,lat2,longe2) {
          base_url = <<https://maps.googleapis.com/maps/api/distancematrix/json?units=imperial&origins=#{lat1},#{longe1}&destinations=#{lat2}%2C#{longe2}&key=#{auth_token}>>;
          url_content = http:get(base_url){"content"}.decode(){"rows"};
          output = url_content.values()[0]{"elements"}[0]{"distance"}{"value"}.defaultsTo(99999);
          output;     
    }
  }

} 