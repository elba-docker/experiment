import datetime

import click
import psycopg2
from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.server.TServer import TThreadPoolServer

from gen_auth.auth import TAuthService
from gen_auth.auth.ttypes import TAccount, TInvalidCredentialsException


class Handler:
  def __init__(self, db_host, db_user):
    self._db_host = db_host
    self._db_user = db_user

  def sign_up(self, username, password, first_name, last_name):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    cursor.execute("""
        INSERT INTO Accounts (username, password, first_name, last_name,
            created_at)
        VALUES ('{username}', '{password}', '{first_name}', '{last_name}',
            '{now}')
        RETURNING id
        """.format(username=username, password=password, first_name=first_name,
            last_name=last_name, now=now))
    account_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return TAccount(id=account_id, username=username, first_name=first_name,
        last_name=last_name, created_at=now)

  def sign_in(self, username, password):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, password, first_name, last_name, created_at
        FROM Accounts
        WHERE username = '{username}'
        """.format(username=username))
    row = cursor.fetchone()
    conn.commit()
    conn.close()
    if row is None:
      raise TInvalidCredentialsException()
    account_id, password_, first_name, last_name, created_at = row
    if password != password_:
      raise TInvalidCredentialsException()
    return TAccount(id=account_id, username=username, first_name=first_name,
        last_name=last_name, created_at=created_at)


class Server:
  def __init__(self, ip_address, port, thread_pool_size, db_host, db_user):
    self._ip_address = ip_address
    self._port = port
    self._thread_pool_size = thread_pool_size
    self._db_host = db_host
    self._db_user = db_user

  def serve(self):
    handler = Handler(self._db_host, self._db_user)
    processor = TAuthService.Processor(handler)
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
