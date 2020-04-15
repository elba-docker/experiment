import datetime

import click
import psycopg2
from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.server.TServer import TThreadPoolServer

from gen_microblog.microblog import TMicroblogService
from gen_microblog.microblog.ttypes import TPost


class Handler:
  def __init__(self, db_host, db_user):
    self._db_host = db_host
    self._db_user = db_user

  def create_post(self, text, author_id, parent_id):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    cursor.execute("""
        INSERT INTO Posts (author_id, parent_id, text, created_at)
        VALUES ({author_id}, {parent_id}, '{text}', '{now}')
        RETURNING id
        """.format(author_id=author_id,
            parent_id=parent_id if parent_id else "null", text=text,
            now=now))
    post_id = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return post_id

  def endorse_post(self, endorser_id, post_id):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    now = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    cursor.execute("""
        INSERT INTO Endorsements (endorser_id, post_id, created_at)
        VALUES ({endorser_id}, {post_id}, '{now}')
        """.format(endorser_id=endorser_id, post_id=post_id, now=now))
    conn.commit()
    conn.close()

  def get_post(self, post_id):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT author_id, parent_id, text, created_at
        FROM Posts
        WHERE id = '{post_id}'
        """.format(post_id=post_id))
    row = cursor.fetchone()
    author_id, parent_id, text, created_at = row
    cursor.execute("""
        SELECT COUNT(*)
        FROM Endorsements
        WHERE post_id = '{post_id}'
        """.format(post_id=post_id))
    n_endorsements = cursor.fetchone()[0]
    conn.commit()
    conn.close()
    return TPost(id=post_id, text=text, author_id=author_id,
        n_endorsements=n_endorsements, parent_id=parent_id)

  def recent_posts(self, n, offset):
    conn = psycopg2.connect("dbname='{dbname}' host='{host}' user={dbuser}".format(
        dbname="microblog_bench", host=self._db_host, dbuser=self._db_user))
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, author_id, parent_id, text, created_at
        FROM Posts
        LIMIT {n} OFFSET {offset}
        """.format(n=n, offset=offset))
    posts = []
    for row in cursor.fetchall():
      post_id, author_id, parent_id, text, created_at = row
      cursor.execute("""
          SELECT COUNT(*)
          FROM Endorsements
          WHERE post_id = '{post_id}'
          """.format(post_id=post_id))
      n_endorsements = cursor.fetchone()[0]
      posts.append(TPost(id=post_id, text=text, author_id=author_id,
          n_endorsements=n_endorsements, parent_id=parent_id))
    conn.commit()
    conn.close()
    return posts


class Server:
  def __init__(self, ip_address, port, thread_pool_size, db_host, db_user):
    self._ip_address = ip_address
    self._port = port
    self._thread_pool_size = thread_pool_size
    self._db_host = db_host
    self._db_user = db_user

  def serve(self):
    handler = Handler(self._db_host, self._db_user)
    processor = TMicroblogService.Processor(handler)
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
