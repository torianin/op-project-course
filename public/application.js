(function() {
  var angel, map;

  $(document).ready(function() {
    var lastStateRequest, playerReady, protocol, requestState, send;

    protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    window.ws = new WebSocket("" + protocol + "//" + window.location.host + "/ws");
    lastStateRequest = 0;
    send = function(message) {
      if (window.ws.readyState === WebSocket.OPEN) {
        return window.ws.send(message);
      }
    };
    requestState = function() {
      var now;

      if (window.ws.readyState !== WebSocket.OPEN) {
        return;
      }
      now = Date.now();
      if (now - lastStateRequest < 33) {
        return;
      }
      lastStateRequest = now;
      return send("j");
    };
    playerReady = function() {
      var index, _ref, _ref1, _ref2;

      if (!((window.map != null) && (window.char != null) && (((_ref = window.data) != null ? _ref.id : void 0) != null))) {
        return false;
      }
      index = window.data.id.indexOf(window.char.id);
      if (index < 0) {
        return false;
      }
      window.char.numer = index;
      return (((_ref1 = window.data.coordinates) != null ? _ref1[index] : void 0) != null) && (((_ref2 = window.data.sizes) != null ? _ref2[index] : void 0) != null);
    };
    window.ws.onopen = function() {
      var str, _ref;

      alertify.success("Podłączono do serwera");
      while (true) {
        str = prompt("Wpisz swój nick: (max 30 znaków, min 2 znaki)", "");
        if (str == null) {
          window.ws.close();
          return;
        }
        str = $.trim(str);
        if ((2 <= (_ref = str.length) && _ref <= 30)) {
          break;
        }
      }
      send("i");
      send("n" + str);
      requestState();
      window.map = new map;
      return cq().framework({
        onresize: function(width, height) {
          this.canvas.width = width;
          return this.canvas.height = height;
        },
        onstep: function(delta, time) {
          var i, _i, _ref1, _results;

          if (!playerReady()) {
            return;
          }
          _results = [];
          for (i = _i = 0, _ref1 = window.data.id.length; 0 <= _ref1 ? _i < _ref1 : _i > _ref1; i = 0 <= _ref1 ? ++_i : --_i) {
            if (window.data.id[i] === window.char.id) {
              window.char.numer = i;
              if (window.data.coordinates[i][0] < this.canvas.width * window.map.move_x_global) {
                window.map.move_x_global -= 1;
              }
              if (window.data.coordinates[i][0] > this.canvas.width * (window.map.move_x_global + 1)) {
                window.map.move_x_global += 1;
              }
              if (window.data.coordinates[i][1] < this.canvas.height * window.map.move_y_global) {
                window.map.move_y_global -= 1;
              }
              if (window.data.coordinates[i][1] > this.canvas.height * (window.map.move_y_global + 1)) {
                _results.push(window.map.move_y_global += 1);
              } else {
                _results.push(void 0);
              }
            } else {
              _results.push(void 0);
            }
          }
          return _results;
        },
        onrender: function(delta, time) {
          var i, _i, _j, _k, _l, _ref1, _ref2, _ref3, _ref4, _results;

          requestState();
          if (!playerReady()) {
            return;
          }
          window.map.move_x = (this.canvas.width / 2) - window.data.coordinates[window.char.numer][0] - window.data.sizes[window.char.numer][0];
          window.map.move_y = (this.canvas.height / 2) - window.data.coordinates[window.char.numer][1] - window.data.sizes[window.char.numer][1];
          this.save().clear("#0e93e8").drawImage(window.map.background, 2000 * (window.map.move_x_global - 1) + window.map.move_x, 1600 * (window.map.move_y_global - 1) + window.map.move_y).drawImage(window.map.background, 2000 * (window.map.move_x_global - 1) + window.map.move_x, 1600 * window.map.move_y_global + window.map.move_y).drawImage(window.map.background, 2000 * (window.map.move_x_global - 1) + window.map.move_x, 1600 * (window.map.move_y_global + 1) + window.map.move_y).drawImage(window.map.background, 2000 * window.map.move_x_global + window.map.move_x, 1600 * (window.map.move_y_global - 1) + window.map.move_y).drawImage(window.map.background, 2000 * window.map.move_x_global + window.map.move_x, 1600 * window.map.move_y_global + window.map.move_y).drawImage(window.map.background, 2000 * window.map.move_x_global + window.map.move_x, 1600 * (window.map.move_y_global + 1) + window.map.move_y).drawImage(window.map.background, 2000 * (window.map.move_x_global + 1) + window.map.move_x, 1600 * (window.map.move_y_global - 1) + window.map.move_y).drawImage(window.map.background, 2000 * (window.map.move_x_global + 1) + window.map.move_x, 1600 * window.map.move_y_global + window.map.move_y).drawImage(window.map.background, 2000 * (window.map.move_x_global + 1) + window.map.move_x, 1600 * (window.map.move_y_global + 1) + window.map.move_y);
          for (i = _i = 0, _ref1 = window.data.id.length; 0 <= _ref1 ? _i < _ref1 : _i > _ref1; i = 0 <= _ref1 ? ++_i : --_i) {
            if (window.data.rotates[i] === 0) {
              this.save().drawImage(window.map.playerimgs[window.data.frames[i]], window.data.coordinates[i][0] + window.map.move_x, window.data.coordinates[i][1] + window.map.move_y, window.data.sizes[i][0], window.data.sizes[i][1]);
            }
            if (window.data.rotates[i] === 1) {
              this.save().drawImage(window.map.playerimgs_rotate[window.data.frames[i]], window.data.coordinates[i][0] + window.map.move_x, window.data.coordinates[i][1] + window.map.move_y, window.data.sizes[i][0], window.data.sizes[i][1]);
            }
            this.save().fillStyle("#000000").font("8pt Arial").wrappedText(window.data.name[i], window.data.coordinates[i][0] + (window.data.sizes[i][0] / 4) + window.map.move_x, window.data.coordinates[i][1] + window.data.sizes[i][0] + 10 + window.map.move_y, 20);
            this.save().fillStyle("#000000").font("11pt Arial").wrappedText("" + window.data.name[i] + ": " + window.data.shooted[i], 20, 20 * (i + 1) + 10, 200);
          }
          for (i = _j = 0, _ref2 = window.data.bullets.length; 0 <= _ref2 ? _j < _ref2 : _j > _ref2; i = 0 <= _ref2 ? ++_j : --_j) {
            this.save().drawImage(window.map.bulletimg, window.data.bullets[i][0] + window.map.move_x, window.data.bullets[i][1] + window.map.move_y);
          }
          if (window.map.showother === 1) {
            for (i = _k = 0, _ref3 = window.data.id.length; 0 <= _ref3 ? _k < _ref3 : _k > _ref3; i = 0 <= _ref3 ? ++_k : --_k) {
              if (i === window.char.numer) {
                this.save().fillStyle("#ff0000").fillRect(((window.data.coordinates[i][0] + window.map.move_x) / 10) + this.canvas.width / 2, (window.data.coordinates[i][1] + window.map.move_y) / 10 + this.canvas.height / 2, 5, 5);
              } else {
                this.save().fillStyle("#FFD700").fillRect(((window.data.coordinates[i][0] + window.map.move_x) / 10) + this.canvas.width / 2, (window.data.coordinates[i][1] + window.map.move_y) / 10 + this.canvas.height / 2, 5, 5);
              }
            }
          }
          _results = [];
          for (i = _l = 0, _ref4 = window.data.bonuses.length; 0 <= _ref4 ? _l < _ref4 : _l > _ref4; i = 0 <= _ref4 ? ++_l : --_l) {
            _results.push(this.save().drawImage(window.map.bonusimg, window.data.bonuses[i][0] + window.map.move_x, window.data.bonuses[i][1] + window.map.move_y).fillStyle("#8E2323").fillRect(((window.data.bonuses[i][0] + window.map.move_x) / 10) + this.canvas.width / 2, (window.data.bonuses[i][1] + window.map.move_y) / 10 + this.canvas.height / 2, 2, 2));
          }
          return _results;
        },
        onmousedown: function(x, y) {
          var d;

          d = new Date();
          return window.p = d.getTime();
        },
        onmouseup: function(x, y) {
          var d, time;

          if (!playerReady()) {
            return;
          }
          d = new Date();
          window.n = d.getTime();
          time = window.n - window.p;
          if (time > 2000) {
            str = prompt("Napisz wiadomość", "Robert");
            if (str != null) {
              send("m" + str);
            }
          }
          return send("p" + (x - window.map.move_x) + "," + (y - window.map.move_y));
        },
        onmousemove: function(x, y) {},
        onkeydown: function(key) {
          if (!playerReady()) {
            return;
          }
          if (key === "r") {
            send("q");
          }
          if (key === "s") {
            send("b");
          }
          if (key === "w") {
            send("t");
          }
          if (key === "d") {
            send("r");
          }
          if (key === "a") {
            send("l");
          }
          if (key === "t") {
            str = prompt("Napisz wiadomość", "Robert");
            if (str != null) {
              return send("m" + str);
            }
          }
        },
        ongamepaddown: function(button, gamepad) {},
        ongamepadup: function(button, gamepad) {},
        ongamepadmove: function(xAxis, yAxis, gamepad) {},
        ondropimage: function(image) {}
      }).appendTo("body");
    };
    window.ws.onmessage = function(evt) {
      if (evt.data.slice(0, 2) === "j:") {
        return window.data = jQuery.parseJSON(evt.data.slice(2));
      } else if (evt.data.slice(0, 2) === "i:") {
        window.char = new angel(evt.data.slice(2));
        return alertify.log(window.char.id);
      } else if (evt.data.slice(0, 2) === "b:") {
        return alertify.success(evt.data.slice(2));
      } else {
        console.log(evt.data.slice(0, 2));
        return alertify.log(evt.data);
      }
    };
    return window.ws.onclose = function() {
      return alertify.error("Nie można podłączyć się do serwera");
    };
  });

  map = (function() {
    function map(data) {
      var i, _i, _j;

      this.move_x = 0;
      this.move_y = 0;
      this.move_x_global = 0;
      this.move_y_global = 0;
      this.backgroundurl = "./img/background.jpeg";
      this.playerimgs = [];
      this.playerimgs_rotate = [];
      for (i = _i = 0; _i < 50; i = ++_i) {
        this.playerimg = new Image();
        this.playerimg.src = "./img/czerwony/" + i + ".png";
        this.playerimgs[i] = this.playerimg;
      }
      for (i = _j = 0; _j < 50; i = ++_j) {
        this.playerimg_rotate = new Image();
        this.playerimg_rotate.src = "./img/czerwony_rotate/" + i + ".png";
        this.playerimgs_rotate[i] = this.playerimg_rotate;
      }
      this.background = new Image();
      this.background.src = this.backgroundurl;
      this.bullet_url = "./img/serceCzerwone.png";
      this.bulletimg = new Image();
      this.bulletimg.src = this.bullet_url;
      this.bonus_url = "./img/bonus0.png";
      this.bonusimg = new Image();
      this.bonusimg.src = this.bonus_url;
      this.showother = 1;
    }

    return map;

  })();

  angel = (function() {
    function angel(id) {
      this.id = parseInt(id, 10);
      this.numer = 0;
    }

    return angel;

  })();

}).call(this);
