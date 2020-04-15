import datetime

import click
import psycopg2
from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.server.TServer import TThreadPoolServer

from gen_sub.sub import TSubService
from gen_sub.sub.ttypes import TSubEntry, TSubNotFoundException


class Handler:
  def __init__(self, db_host, db_user):
    self._db_host = db_host
    self._db_user = db_user

  def create_subscription(self, subscriber_id, channel_name):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    cursor.execute("""
        INSERT INTO Subscriptions (subscriber_id, channel_name, created_at)
        VALUES ({subscriber_id}, '{channel_name}', '{now}')
        RETURNING id
        """.format(subscriber_id=subscriber_id, channel_name=channel_name,
            now=now))
    subscription_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return TSubEntry(id=subscription_id, subscriber_id=subscriber_id,
        channel_name=channel_name, created_at=now)

  def delete_subscription(self, subscription_id):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        DELETE FROM Subscriptions WHERE id = {subscription_id}
        """.format(subscription_id=subscription_id))
    conn.commit()
    conn.close()
    return None

  def get_subscription(self, subscriber_id, channel_name):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, created_at
        FROM Subscriptions
        WHERE subscriber_id = {subscriber_id} AND
            channel_name = '{channel_name}'
        """.format(subscriber_id=subscriber_id, channel_name=channel_name))
    row = cursor.fetchone()
    conn.commit()
    conn.close()
    if row is None:
      raise TSubNotFoundException()
    subscription_id, created_at = row
    return TSubEntry(id=subscription_id, subscriber_id=subscriber_id,
        channel_name=channel_name, created_at=created_at)

  def get_subscribers_of_channel(self, channel_name):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, subscriber_id, created_at
        FROM Subscriptions
        WHERE channel_name = '{channel_name}'
        """.format(channel_name=channel_name))
    rows = cursor.fetchall()
    conn.commit()
    conn.close()
    return [
        TSubEntry(id=subscription_id, subscriber_id=subscriber_id,
            channel_name=channel_name, created_at=created_at)
        for (subscription_id, subscriber_id, created_at) in rows
    ]

  def get_channels_subscribed_by(self, subscriber_id):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, channel_name, created_at
        FROM Subscriptions
        WHERE subscriber_id = {subscriber_id}
        """.format(subscriber_id=subscriber_id))
    rows = cursor.fetchall()
    conn.commit()
    conn.close()
    return [
        TSubEntry(id=subscription_id, subscriber_id=subscriber_id,
            channel_name=channel_name, created_at=created_at)
        for (subscription_id, channel_name, created_at) in rows
    ]


class Server:
  def __init__(self, ip_address, port, thread_pool_size, db_host, db_user):
    self._ip_address = ip_address
    self._port = port
    self._thread_pool_size = thread_pool_size
    self._db_host = db_host
    self._db_user = db_user

  def serve(self):
    handler = Handler(self._db_host, self._db_user)
    processor = TSubService.Processor(handler)
    transport = TSocket.TServerSocket(host=self._ip_address, port=self._port)
    tfactory = TTransport.TBufferedTransportFactory()
    pfactory = TBinaryProtocol.TBinaryProtocolFactory()
    tserver = TThreadPoolServer(processor, transport, tfactory, pfactory)
    tserver.setNumThreads(self._thread_pool_size)
    tserver.serve()


@click.command()
@click.option("--ip_address", prompt="IP Address")
@click.option("--port", prompt="Port")
@click.option("--thread_pool_size", prompt="Thread pool size", type=click.INT)
@click.option("--db_host", prompt="PostgreSQL host")
@click.option("--db_user", prompt="PostgreSQL user")
def main(ip_address, port, thread_pool_size, db_host, db_user):
  server = Server(ip_address, port, thread_pool_size, db_host, db_user)
  server.serve()


if __name__ == "__main__":
  main()
