#!/bin/bash

cd $(dirname $0)/..

. ./env_local.sh

psql -h $PGHOST -p $PGPORT $DBNAME -f `pwd`/../schemas/articles.sql

psql -h $PGHOST -p $PGPORT $DBNAME -c """copy articles from '$(pwd)/data/reuters/converted.csv' csv;"""


