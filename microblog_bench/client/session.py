import os
import random

import click
import requests

import wise_load


class MicroblogSession(wise_load.Session):
  def __init__(self, session_config_filename, hostname, port, prefix):
    super().__init__(session_config_filename)
    self._username = self.random_string(10)
    self._password = self.random_string(10)
    self._first_name = self.random_string(10)
    self._last_name = self.random_string(10)
    self._post_to_read = None
    self._post_to_endorse = None
    self._user_to_subscribe = None
    self._url_prefix = "http://{hostname}:{port}/{prefix}".format(
        hostname=hostname, port=port, prefix=prefix)

  def sign_up(self):
    requests.post(self._url_prefix + "/account",
        json={
            "username": self._username,
            "password": self._password,
            "first_name": self._first_name,
            "last_name": self._last_name
        })

  def create_post(self):
    requests.post(self._url_prefix + "/post",
        auth=(self._username, self._password),
        json={
            "text": self.random_string(140)
        })

  def endorse_post(self):
    if self._post_to_endorse is not None:
      requests.post(
          self._url_prefix + "/endorsement/%s" % self._post_to_endorse,
          auth=(self._username, self._password))
      self._post_to_endorse = None

  def view_inbox(self):
    r = requests.get(self._url_prefix + "/inbox",
        auth=(self._username, self._password))
    try:
      posts = r.json()
      if posts:
        self._post_to_read = random.choice(posts)["id"]
        self._user_to_subscribe = random.choice(posts)["author_id"]
    except ValueError as e:
      print(f"Error: could not fetch route /inbox:\n{e}")

  def view_recent_posts(self):
    r = requests.get(self._url_prefix + "/post",
        auth=(self._username, self._password))
    try:
      posts = r.json()
      if posts:
        self._post_to_read = random.choice(posts)["id"]
        self._user_to_subscribe = random.choice(posts)["author_id"]
    except ValueError as e:
      print(f"Error: could not fetch route /post:\n{e}")

  def subscribe_to_user(self):
    if self._user_to_subscribe is not None:
      requests.post(
          self._url_prefix + "/subscription/%s" % self._user_to_subscribe,
          auth=(self._username, self._password))
      self._user_to_subscribe = None


@click.command()
@click.option("--config", prompt="Configuration file")
@click.option("--hostname", prompt="Hostname")
@click.option("--port", prompt="Port", type=click.INT)
@click.option("--prefix", default="")
def main(config, hostname, port, prefix):
  workload = wise_load.Workload(MicroblogSession, config, hostname, port,
      prefix)
  workload.start()


if __name__ == "__main__":
  main()
