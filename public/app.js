var Tube = {};

function HandleTubeStateChange(value) {
	console.log('Tube state change: ' + value);
	
	if (value == 1) {
		if (Tube.player.getVideoUrl() != Tube.url) {
			NotifyNewVideoPlaying(Tube.player.getVideoUrl());
			Tube.url = Tube.player.getVideoUrl();
		}
		if (!Tube.interval) {
			Tube.interval = setInterval(function(){
				console.log('SYNC TO TIME');
				Tube.socket.sendJSON({'type': 'video_time', 'channel_id': Tube.current_channel, 'time': Tube.player.getCurrentTime()});
			}, 2000);
		}
	} else if (value == 0) {
		if (Tube.interval)
		  clearInterval(Tube.interval);
		Tube.interval = null;
	}
};

function HandleTubeError(code) {
	console.log('Tube error: ' + code);
};


function onYouTubePlayerReady(playerId) {
  if (Tube.interval)
    clearInterval(Tube.interval);
  Tube.player = document.getElementById("video");
  Tube.player.playVideo();

  if (Tube.admin) {
    Tube.player.addEventListener("onStateChange", 'HandleTubeStateChange');
    Tube.player.addEventListener("onError", 'HandleTubeError');
  }
}

function NotifyNewVideoPlaying(url) {
	Tube.socket.sendJSON({'type': 'video', 'url': url, 'time': 0, 'channel_id': Tube.current_channel});
}

function setVideoID(id) {
	if (Tube.player && Tube.player.getVideoUrl() == Tube.url)
		return;
	if (Tube.player) {
		Tube.player.loadVideoById(id);
	} else {
		var params = { allowScriptAccess: "always" };
		var attrs = { id: "video" };
		Tube.url = "http://www.youtube.com/e/" + id + "?enablejsapi=1&playerapiid=ytplayer";
		swfobject.embedSWF(Tube.url, "video", "425", "356", "8", null, null, params, attrs);
	}
}

$(document).ready(function(){
	if (!$('#video'))
		return;
	
	console.log("CONNECT",document.location.host + "/ws")
	WebSocket.prototype.sendJSON = function(data){
		this.send(JSON.stringify(data));
	};
	Tube.socket = new WebSocket("ws://" + document.location.host + "/ws");
	Tube.socket.onmessage = function(evt) {
		var message = JSON.parse(evt.data);
		$("#messages").append("<p>"+evt.data+"</p>");
		
		if (message.type == 'hello') {
			this.onauthenticated(message);
		} else if (message.type == 'userjoined') {
			if (Tube.user == message.user) {
				Tube.admin = (message['scope']||[]).indexOf('admin') >= 0;
			}
		} else if (message.type == 'video') {
			if (!Tube.admin) {
				setVideoID(message.url);
			}
		} else if (message.type == 'video_time') {
			// Set the time of the video, ignoring minor offsets
			if (!Tube.admin && Tube.player) {
			  var currentTime = Tube.player.getCurrentTime();
			  if ((message.time - currentTime < -1.0) || (message.time - currentTime > 1.0))
			  	Tube.player.seekTo(message.time, true);
			}
		}
	};
	Tube.socket.onclose = function() {
		$('#status').html('Closed');
	};
	Tube.socket.onopen = function() {
		var self = this;
		Tube.admin = false;
		$('#status').html('Connected');
		
		$.ajax({type: 'POST', url: '/auth/socket_token', success: function(data){
			self.sendJSON({'type': 'auth', 'auth_token': data.auth_token});
		}, error: function(xhr, status, error){
			console.log('BARF', status, error);
			self.close();
		}});
	};
	Tube.socket.onauthenticated = function(message) {
		Tube.user = message.user;
		this.sendJSON({'type': 'subscribe', 'channel_id': Tube.current_channel});
	};
	
	$('#status').html('Connecting...');
});