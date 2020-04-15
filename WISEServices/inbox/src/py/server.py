import datetime

import click
import psycopg2
from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.server.TServer import TThreadPoolServer

from gen_inbox.inbox import TInboxService
from gen_inbox.inbox.ttypes import TMessage


class Handler:
  def __init__(self, db_host, db_user):
    self._db_host = db_host
    self._db_user = db_user

  def push(self, inbox_name, message_text):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    cursor.execute("""
        INSERT INTO Messages (inbox_name, text, created_at)
        VALUES ('{inbox_name}', '{message_text}', '{now}')
        RETURNING id
        """.format(inbox_name=inbox_name, message_text=message_text, now=now))
    message_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return message_id

  def fetch(self, inbox_name, n, offset):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, text, created_at
        FROM Messages
        WHERE inbox_name = '{inbox_name}'
        ORDER BY created_at DESC
        LIMIT {n} OFFSET {offset}
        """.format(inbox_name=inbox_name, n=n, offset=offset))
    rows = cursor.fetchall()
    conn.commit()
    conn.close()
    return [
        TMessage(id=message_id, text=message_text, created_at=created_at)
        for (message_id, message_text, created_at) in rows
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
    processor = TInboxService.Processor(handler)
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
