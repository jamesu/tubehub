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
    foreman start -f Procfile.development

Then go to [http://localhost:5000](http://localhost:5000)

To administer, go to [http://localhost:5000/admin](http://localhost:5000/admin) and login as 'admin' using 'password' as the password. 

Have fun!