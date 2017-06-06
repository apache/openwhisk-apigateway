#!/bin/bash

cqlsh 127.0.0.1 9042 --cqlversion="3.4.4" -f tools/cassandra/schema.csql
