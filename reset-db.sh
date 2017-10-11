dropdb -h dcache-dir-xfel01 -U postgres c3 
createdb -h dcache-dir-xfel01 -U postgres c3
psql -h dcache-dir-xfel01 -U postgres c3 -f reset.sql
