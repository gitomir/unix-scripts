#!/usr/bin/python

from senderbase import SenderBase


with open('ip-list.txt') as file:
   for ip in file:
       sb = SenderBase(timeout=30)
       my_result = sb.lookup(ip)
       print "Lookup IP:",ip," senderbase.org:",my_result
       print 
