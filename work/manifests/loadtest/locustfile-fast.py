import random
from locust import HttpUser, TaskSet, between

products = [
    "0PUK6V6EV0", "1YMWWN1N4O", "2ZYFJ3GM2N", "66VCHSJNUP",
    "6E92ZMYYFZ", "9SIQT8TOJO", "L9ECAV7KIM", "LS4PSXUNUM", "OLJCESPC7Z",
]

def index(l):
    l.client.get("/")

def browseProduct(l):
    l.client.get("/product/" + random.choice(products))

def addToCart(l):
    product = random.choice(products)
    l.client.get("/product/" + product)
    l.client.post("/cart", {"product_id": product, "quantity": random.choice([1, 2, 3])})

class UserBehavior(TaskSet):
    tasks = {index: 3, browseProduct: 5, addToCart: 2}

    def on_start(self):
        index(self)

class WebsiteUser(HttpUser):
    tasks = [UserBehavior]
    wait_time = between(0.1, 0.3)
