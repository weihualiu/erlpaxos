#!/bin/bash
cd conf
erl -pa ../ebin -name erlpaxos -setcookie paxos -boot start_sasl -config log -s erlpaxos start