import datetime

import click
import psycopg2
from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.server.TServer import TThreadPoolServer

from gen_queue.queue import TQueueService
from gen_queue.queue.ttypes import TQueueEntry, TEmptyQueueException


class Handler:
  def __init__(self, db_host, db_user):
    self._db_host = db_host
    self._db_user = db_user

  def enqueue(self, queue_name, message, expires_at):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    cursor.execute("""
        INSERT INTO QueueEntries (queue_name, message, created_at, expires_at)
        VALUES ('{queue_name}', '{message}', '{now}', '{expires_at}')
        RETURNING id
        """.format(queue_name=queue_name, message=message, now=now,
            expires_at=expires_at))
    queue_entry_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return queue_entry_id

  def dequeue(self, queue_name):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, message, created_at, expires_at
        FROM QueueEntries
        WHERE queue_name = '{queue_name}'
        ORDER BY created_at ASC
        LIMIT 1
        """.format(queue_name=queue_name))
    row = cursor.fetchone()
    if row is None:
      conn.commit()
      conn.close()
      raise TEmptyQueueException()
    else:
      queue_entry_id, message, created_at, expires_at = row
      cursor.execute("""
          DELETE FROM QueueEntries WHERE id = {queue_entry_id}
          """.format(queue_entry_id=queue_entry_id))
      conn.commit()
      conn.close()
      return TQueueEntry(id=queue_entry_id, queue_name=queue_name,
          message=message, created_at=created_at, expires_at=expires_at)


class Server:
  def __init__(self, ip_address, port, thread_pool_size, db_host, db_user):
    self._ip_address = ip_address
    self._port = port
    self._thread_pool_size = thread_pool_size
    self._db_host = db_host
    self._db_user = db_user

  def serve(self):
    handler = Handler(self._db_host)
    processor = TQueueService.Processor(handler)
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
