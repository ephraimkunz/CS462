import requests
sensor_collection_eci = "HB31f6RaaX1nmeCbYp6DZn"

def create_sensor(name):
    resp = requests.get("http://localhost:8080/sky/event/{}/1/sensor/new_sensor?name={}".format(sensor_collection_eci, name));
    return resp.json()

def remove_sensor(name):
    resp = requests.get("http://localhost:8080/sky/event/{}/1/sensor/unneeded_sensor?name={}".format(sensor_collection_eci, name));
    return resp.json()

def get_sensors():
    resp = requests.get("http://localhost:8080/sky/cloud/{}/manage_sensors/sensors".format(sensor_collection_eci))
    return resp.json()
    
def count_sensors():
    resp = get_sensors()
    count = len(resp.keys())
    return count

def get_profile(eci):
    resp = requests.get("http://localhost:8080/sky/cloud/{}/sensor_profile/get_profile".format(eci))
    return resp.json()

def send_hearbeat(eci):
    resp = requests.post("http://localhost:8080/sky/event/{}/1/wovyn/heartbeat".format(eci), json={"genericThing": {"data": {"temperature": [{"temperatureF": 101.5}]}}})

def get_all_temps():
    resp = requests.get("http://localhost:8080/sky/cloud/{}/manage_sensors/getAllTemps".format(sensor_collection_eci))
    return resp.json()

# Create 5 sensors
create_sensor("1")
create_sensor("2")
create_sensor("3")
create_sensor("4")
create_sensor("5")

assert count_sensors() == 5

remove_sensor("3")

assert count_sensors() == 4

# Send a temp event to each sensor
sensors = get_sensors()
for key in sensors.keys():
    send_hearbeat(sensors[key]["eci"])

# Make sure they each made it through
temps = get_all_temps()
assert len(temps) == 4
for temp in temps.keys():
    assert len(temps[temp]) == 9

# Check sensor profiles setup right
for key in sensors.keys():
    profile = get_profile(sensors[key]["eci"])
    assert key == profile["name"]
    assert 77.5 == profile["high"]



