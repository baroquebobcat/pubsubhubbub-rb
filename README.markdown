#PubSubHubbub-rb

A Ruby port of Google's PubSubHubbub reference implementation. The example was implemented using Monk, Sinatra, Redis, Thin, and Nginx. The project includes tests and basic configuration examples.

The project is an implementation of the actual hub, and does not include publisher and subscriber client libraries.

Here's a link to Google's PubSubHubbub reference implementation

 * http://code.google.com/p/pubsubhubbub/

(barinek@gmail.com)

##Motivation

The project was a bit accidental and essentially the result of a review of the PubSubHubbub specification.

##Direction

Next steps for the port are a bit unclear. So far it's been a move of everything to Ruby using a light-weight tool chain in order to get the test suite to pass. Next steps are likely refactoring and scale.

##Todo

 * Implement periodic workers
 * Address unicode support
 * Complete the test suite
 * Address basic queue support

#Requirements

Package dependencies

 * Ruby
 * RubyGems
 * Nginx
 * Redis (provided)

##Ruby Gems

Here are the gems you need to install locally

 * dependencies (0.0.7)
 * nokogiri (1.4.1)
 * thin (1.2.4)
 * thor (0.12.0)

**Redis**

You'll need to make redis locally

      cd vendor/redis-1.02
      make
      cd

#Testing

Running redis for testing (port 6380)

      thor monk:redis:test

Running the tests

      thor monk:test

#Starting Application

Running redis for development (port 6379)

      thor monk:redis:test

Running the application

      thor monk:start

##Stopping Redis

      thor monk:redis:stop

#License

Copyright 2010 Michael Barinek

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

