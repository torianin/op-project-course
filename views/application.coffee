$(document).ready ->
  alertify.prompt "Podaj nick", ((e, str) -> 
    if e
      window.ws = new WebSocket("ws://torianinmobile.pl:8080")
      window.ws.onopen = ->
        alertify.success "Connected to server"
        window.ws.send str
        $.getJSON "http://torianinmobile.pl/api/map.json", (data) ->
          window.data = data
          window.map = new map
          cq().framework(
            onResize: (width, height) ->
              @canvas.width = width
              @canvas.height = height

            onStep: (delta) ->
              $.getJSON "http://torianinmobile.pl/api/map.json", (data) ->
                window.data = data

            onRender: ->
              @save()
                .clear("#00a2e8")
                .drawImage(window.map.background, 0, 0)
                .drawImage(window.map.background, 640, 0)
                .drawImage(window.map.background, 1280, 0)
              for i in [0...window.data.id.length]
                @save()
                  .drawImage(window.map.playerimg, window.data.coordinates[i][0], window.data.coordinates[i][1])
                  .fillStyle("#000000")
                  .wrappedText window.data.name[i], window.data.coordinates[i][0]+5, window.data.coordinates[i][1]+70, 20

            onMouseDown: (x, y) ->
              alertify.success "#{x}, #{y}"

            onMouseUp: (x, y) ->

            onMouseMove: (x, y) ->

            onKeyDown: (key) ->
              window.ws.send "b" if key is ("s" or "down") # Down
              window.ws.send "t" if key is ("w" or "up") # Up
              if key is ("d" or "right") # Right  
                window.map.playerimg.src = window.map.url
                window.ws.send "r" 
              if key is ("a" or "left") # Left  
                window.map.playerimg.src = window.map.url_rotate
                window.ws.send "l" 
              if key is "t" # Right  
                str = prompt("Napisz wiadomosc","")
                window.ws.send "m#{str}"


            onKeyUp: (key) ->

            onSwipe: (direction) ->
              window.ws.send "b" if direction is "down" # Down
              window.ws.send "t" if direction is "up" # Up
              if direction is "right" # Right  
                window.map.playerimg.src = window.map.url
                window.ws.send "r" 
              if direction is "left" # Right  
                window.map.playerimg.src = window.map.url_rotate
                window.ws.send "l" 

            onDropImage: (image) ->

            ).appendTo "body"

      window.ws.onmessage = (evt) ->
        alertify.log(evt.data)

      window.ws.onclose = ->
        alertify.error("Can't connect to server")
    else
      # user clicked "cancel"
    ), "Robert"

class map
  constructor: (data)  ->
    @url = "./img/angel.png"
    @url_rotate = "./img/angel_rotate.png"
    @backgroundurl = "./img/background.png"
    @playerimg = new Image()
    @playerimg.src = @url
    @background = new Image()
    @background.src = @backgroundurl

