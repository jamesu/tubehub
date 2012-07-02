# TubeHub

## What is it?

TubeHub is a synchronized Youtube playlist which lets you watch youtube videos in sync with anyone over the internet using Websockets.

There are no user accounts in TubeHub except for administration. Everyone is Anonymous, though [Tripcodes](http://wiki.iiichan.net/Tripcode) are supported for those who wish to maintain a persistent identity.

## What about a demo?

A demonstration is available at:

[http://testtube.cuppadev.co.uk/](http://testtube.cuppadev.co.uk/)

## Sounds great, how do i install it?

TestTube can run out of the box off of a local sqlite database by running the following commands:

    bundle install
    rake db:load
    rake db:seed
    foreman start -f Procfile.single.development

Then go to [http://localhost:5000](http://localhost:5000)

To administer, go to [http://localhost:5000/admin](http://localhost:5000/admin) and login as 'admin' using 'password' as the password. 

## I need to scale. How do i run more servers?

TubeHub can optionally be run in "multiple server" mode. With this you can run multiple backend services for each channel.

A [Redis](http://redis.io/) server is required to facilitate communication between the frontend and backend. You can point TubeHub to your redis server in app.yml:

	redis_url: redis://127.0.0.1:6379/0
	redis_channel: tubehub

Set the "TUBEHUB_MODE" environment variable to either "frontend" for the web service, or "backend" for the websocket server. And example of this can be found in Procfile.multi.development:

	web: env TUBEHUB_MODE=frontend bundle exec thin-websocket -e development -R config.ru start -p $PORT
	web_slave: env TUBEHUB_MODE=backend bundle exec thin-websocket -e development -R config.ru start -p $PORT

For each channel, you will have to set the "Backend server port" setting to one of your backend services. Users will then connect to that server when visting the channel.

Have fun!