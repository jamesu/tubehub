var ChatManager = function(){
}

ChatManager.prototype.onmessage = function(user_id, message){
    /*var el = $('#overlaycanvas').append("<div class='msg'><strong></strong><div></div></div>").children().last();
    el.children('div').text(content);
    el.children('strong').text(Tube.userList[user_id].name + ':');

    el.css({'top': (Math.random()*300) + 'px', 'left': '410px', 'color': Tube.userList[user_id].color});

    var length = el.width();
    var time = (400.0 / length) * 1.0 * 1000;
    console.log('tt',message.content,length,time);
    
    el.animate({left: '-=' + (length + 410) + 'px'}, time, 'linear', function(){ el.remove(); });*/
    
	var messages = $('#messages');
	var atBottom = messages[0].scrollHeight - messages[0].scrollTop < 201;
	var el = messages.append('<div><div class="user"></div><div class="msg"></div></div>').children().last();
	el.children('.msg').text(message);
	el.children('.user').text(Tube.userList[user_id].get('name') + ':');
	
	if (atBottom)
    	messages[0].scrollTop = messages[0].scrollHeight;
};

ChatManager.prototype.onchangename = function(user_id, old_name){
    //$('#user_' + message.uid).text(Tube.userList[user_id].name);
    var el = $('#messages').append('<div><strong class="u1"></strong> is now known as <strong class="u2"></strong>').children().last();
    el.children('.u1').text(old_name);
    el.children('.u2').text(Tube.userList[user_id].get('name'));
}

Tube.chat = new ChatManager();