#!/usr/bin/env python

import psycopg2
import sys

REG = 0100000
DIR = 0040000
SLINK = 0120000

def connect(dbname, user, host='localhost', password=''):

  return psycopg2.connect("dbname='%s' user='%s' host='%s' password='%s'" % (dbname, user, host, password))


def dump_location(in_cur, out_cur, inode):
  in_cur.execute("select * from t_locationinfo where inumber=%s", (inode,))
  rows = in_cur.fetchall()
  for row in rows:
    out_cur.execute("INSERT INTO t_locationinfo VALUES(%s, %s, %s, %s, %s, %s, %s)", row);

def dump_level(in_cur, out_cur, inode, levels=[1, 2, 3, 4, 5, 6, 7]):

  for level in levels:
    in_cur.execute("select * from t_level_%s where inumber='%s'" % (level, inode))
    rows = in_cur.fetchall()
    for row in rows:
      out_cur.execute("INSERT INTO t_level_" + str(level) + " VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)", row)

def dump_storageinfo(in_cur, out_cur, inode):

  in_cur.execute("select * from t_storageinfo where inumber=%s", (inode,))
  rows = in_cur.fetchall()
  for row in rows:
    out_cur.execute("INSERT INTO t_storageinfo VALUES(%s, %s, %s, %s)", row)

def dump_acl(in_cur, out_cur, inode):

  in_cur.execute("select * from t_acl where inumber=%s", (inode,))
  rows = in_cur.fetchall()
  for row in rows:
    out_cur.execute("INSERT INTO t_acl VALUES(%s, %s, %s, %s, %s, %s, %s, %s)", row)

def dump_inode_checksum(in_cur, out_cur, inode):

  in_cur.execute("select * from t_inodes_checksum where inumber=%s",(inode,))
  rows = in_cur.fetchall()
  for row in rows:
    out_cur.execute("INSERT INTO t_inodes_checksum VALUES(%s, %s, %s)", row)

def dump_inodes_data(in_cur, out_cur, inode):

  in_cur.execute("select * from t_inodes_data where inumber=%s",(inode,))
  rows = in_cur.fetchall()
  for row in rows:
    out_cur.execute("INSERT INTO t_inodes_data VALUES(%s, %s)", row)

def dump_inode(in_cur, out_cur, inode):

  in_cur.execute("select * from t_inodes where inumber=%s", (inode,))
  rows = in_cur.fetchall()
  out_cur.execute("INSERT INTO t_inodes VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)", rows[0])

 
def reset_nlink(out_cur, inode):
  print "update table: t_inodes_data"
  out_cur.execute("UPDATE t_inodes SET inlink=2 WHERE inumber=%s", (inode,))
  
def dump_tags(in_cur, out_cur, source_inode, primary):

  print "dumping tags"
  in_cur.execute("select itagname, itagid, isorign from t_tags where inumber=%s", (source_inode,))
  rows = in_cur.fetchall()
  for row in rows:
    (itagname, itagid, isorigin) = row
    if primary and isorigin == 0:
        continue;
    dump_tag(in_cur, out_cur, itagid)
    cp_tag = (source_inode, itagid, 1, itagname)
    out_cur.execute("DELETE FROM t_tags WHERE inumber=%s AND itagname=%s", (source_inode, itagname))
    out_cur.execute("INSERT INTO t_tags VALUES( %s, %s, %s, %s)", cp_tag)
    

def dump_tag(in_cur, out_cur, tagid):

  in_cur.execute("select * from t_tags_inodes where itagid=%s",  (tagid,))
  rows = in_cur.fetchall()
  print "passing table: t_tags_inodes"
  for row in rows:
    out_cur.execute("INSERT INTO t_tags_inodes VALUES( %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)", row)

def get_inuber(cur, pnfsid):
  cur.execute("select inumber from t_inodes where ipnfsid=%s",  (pnfsid,))
  rows = cur.fetchall()
  return rows[0]

def dump_dir(in_cur, out_db, root):

  out_cur = out_db.cursor()
  in_cur.execute("select t_inodes.inumber, t_dirs.iname, t_inodes.itype from t_inodes, t_dirs where t_dirs.iparent=%s and t_inodes.inumber=t_dirs.ichild", (root,))
  rows = in_cur.fetchall()

  print "processing %d records"  % (in_cur.rowcount)
  for row in rows:
    (inode, name, type) = row

    dump_inode(in_cur, out_cur, inode)
    add_to_dir(out_cur, inode, root, name)
    dump_acl(in_cur, out_cur, inode)

    if type == DIR:
      reset_nlink(out_cur, inode)
      dump_tags(in_cur, out_cur, inode, True)
      print "commiting dir %d %s" % (inode, name)
      out_db.commit()
      dump_dir(in_cur, out_db, inode)
    elif type ==  REG:
      dump_location(in_cur, out_cur, inode)
      dump_level(in_cur, out_cur, inode)
      dump_inode_checksum(in_cur, out_cur, inode)
      dump_storageinfo(in_cur, out_cur, inode)
      out_db.commit()
    elif type == SLINK:
      dump_inodes_data(in_cur, out_cur, inode)
      out_db.commit()

def add_to_dir(out_cur, child, parent, name):

   out_cur.execute("INSERT INTO t_dirs VALUES(%s, %s, %s)", (parent, child, name))
   out_cur.execute("UPDATE t_inodes SET inlink=inlink+1 WHERE inumber=%s", (parent,))

def fix_inumber(cur):

  cur.execute("select max(inumber) from t_inodes")
  maxval = cur.fetchall()[0]
  cur.execute("select setval('t_inodes_inumber_seq', %s)", (maxval,))

def bump_inumber(in_cur, out_cur):

  in_cur.execute("select max(inumber) from t_inodes")
  maxval_in = in_cur.fetchall()[0]
  out_cur.execute("select max(inumber) from t_inodes")
  maxval_out = out_cur.fetchall()[0]
  if maxval_in > maxval_out:
    print "bump_inumber of the dest_db updating %s records, delta %s " % (maxval_out,maxval_in,)
    out_cur.execute("update t_inodes set inumber = inumber+%s", (maxval_in,))
  else:
    print "bump_inumber of the source_db updating %s records, delta %s" % (maxval_in,maxval_out,)
    in_cur.execute("update t_inodes set inumber = inumber+%s", (maxval_out,))


def bump_itagid(in_cur, out_cur):

  in_cur.execute("select max(itagid) from t_tags_inodes")
  maxval_in = in_cur.fetchall()[0]
  out_cur.execute("select max(itagid) from t_tags_inodes")
  maxval_out= out_cur.fetchall()[0]
  print "max tag out %s in %s !" % (maxval_out, maxval_in )
  out_cur.execute("update t_tags_inodes set itagid = itagid+%s+%s", (maxval_in,maxval_out,))
  out_cur.execute("update t_tags_inodes set itagid = itagid-%s", (maxval_out,))



if __name__ == '__main__':

  try:
    import dumptree_settings
    from dumptree_settings import *
  except ImportError:
    dependency_error('Unable to read dumptree_settings.py.')

  in_db = connect(dbname=source_db, user=source_db_user, host=source_db_host)
  out_db = connect(dbname=dest_db, user=dest_db_user, host=dest_db_host)
  import_name = '%s_IMPORT' % source_inode

  in_cur = in_db.cursor()
  out_cur = out_db.cursor()

  print "bump_itagid"
  bump_itagid(in_cur, out_cur)

  print "bump_inumber"
  bump_inumber(in_cur, out_cur)

  in_inumber  = get_inuber(in_cur, source_inode)
  out_inumber = get_inuber(out_cur, dest_inode)

  print "dump_inode"
  dump_inode(in_cur, out_cur, in_inumber)
  add_to_dir(out_cur, in_inumber, out_inumber, import_name)

  print "reset_nlink"
  reset_nlink(out_cur, in_inumber)

  print "dump_tags"
  dump_tags(in_cur, out_cur, in_inumber, False)
  print "dump_acl"
  dump_acl(in_cur, out_cur, in_inumber)
  out_db.commit()
  print "dump_dir"
  dump_dir(in_cur, out_db, in_inumber)

  out_cur = out_db.cursor()
  print "fix_inumber"
  fix_inumber(out_cur)
  print "final commit"
  out_db.commit()

