$(document).ready ->
  alertify.prompt "Podaj nick", ((e, str) -> 
    if e
      window.ws = new WebSocket("ws://torianinmobile.pl:8080")
      window.ws.onopen = ->
        alertify.success "Connected to server"
        window.ws.send str
        window.ws.send "i"
        window.ws.send "j"
        window.map = new map

      window.ws.onmessage = (evt) ->
        if evt.data[0..1] is "j:"
          window.data = jQuery.parseJSON(evt.data[2..evt.data.size])

        else if  evt.data[0..1] is "i:"
          window.char = new angel evt.data[2..evt.data.size]
          alertify.log(window.char.id)

        else
          console.log(evt.data[0..1])
          alertify.log(evt.data)

      window.ws.onclose = ->
        alertify.error("Can't connect to server")
        
      cq().framework(
        onResize: (width, height) ->
          @canvas.width = width
          @canvas.height = height

        onStep: (delta) ->
          for i in [0...window.data.id.length]
            if window.data.id[i] is window.char.id
              if window.data.coordinates[i][0] < 0 + window.map.move_x
                window.map.move_x -= 100
             if window.data.coordinates[i][0] > @canvas.width + window.map.move_x
                window.map.move_x += 100
              if window.data.coordinates[i][1] < 0 + window.map.move_y
                window.map.move_y -= 100
              if window.data.coordinates[i][1] > @canvas.height + window.map.move_y
                window.map.move_y += 100

        onRender: ->
          window.ws.send "j"
          @save()
            .clear("#00a2e8")
            .drawImage(window.map.background, 0, 0)
            .drawImage(window.map.background, 640, 0)
            .drawImage(window.map.background, 1280, 0)
          for i in [0...window.data.id.length]
            if window.data.rotates[i] is 0 
              @save()
                .drawImage(window.map.playerimg, window.data.coordinates[i][0]-window.map.move_x, window.data.coordinates[i][1]-window.map.move_y,window.data.sizes[i][0],window.data.sizes[i][1])
            if window.data.rotates[i] is 1
              @save()  
                .drawImage(window.map.playerimg_rotate, window.data.coordinates[i][0]-window.map.move_x, window.data.coordinates[i][1]-window.map.move_y,window.data.sizes[i][0],window.data.sizes[i][1])
            @save()
              .fillStyle("#000000")
              .wrappedText window.data.name[i], window.data.coordinates[i][0]+(window.data.sizes[i][0]/4)-window.map.move_x, window.data.coordinates[i][1]+window.data.sizes[i][0]+10-window.map.move_y, 20
          for i in [0...window.data.bullets.length]
            @save()
              .drawImage(window.map.bulletimg, window.data.bullets[i][0]-window.map.move_x, window.data.bullets[i][1]-window.map.move_y)

        onMouseDown: (x, y) ->
          d = new Date()
          window.p = d.getTime()
          alertify.success "#{x}, #{y}"

        onMouseUp: (x, y) ->
          d = new Date()
          window.n = d.getTime()
          time = window.n - window.p
          alertify.success "#{time}"
          if time > 2000
            str = prompt("Napisz wiadomosc","Robert")
            window.ws.send "m#{str}"
          if time > 200         
            window.ws.send "p#{x+ window.map.move_x},#{y + window.map.move_y}"

        onMouseMove: (x, y) ->

        onKeyDown: (key) ->
          window.ws.send "b" if key is ("s") # Down
          window.ws.send "t" if key is ("w") # Up
          if key is ("d") # Right  
            window.ws.send "r" 
          if key is ("a") # Left  
            window.ws.send "l" 
          if key is "t" # Right  
            str = prompt("Napisz wiadomosc","Robert")
            window.ws.send "m#{str}"

        onKeyUp: (key) ->

        onSwipe: (direction) ->
          window.ws.send "b" if direction is "down" # Down
          window.ws.send "t" if direction is "up" # Up
          if direction is "right" # Right  
            window.ws.send "r" 
          if direction is "left" # Right  
            window.ws.send "l" 

        onDropImage: (image) ->

        ).appendTo "body"

    else
      # user clicked "cancel"
    ), "Robert"


class map
  constructor: (data)  ->
    @move_x = 0
    @move_y = 0
    @url = "./img/angel.png"
    @url_rotate = "./img/angel_rotate.png"
    @backgroundurl = "./img/background.png"
    @playerimg = new Image()
    @playerimg.src = @url
    @playerimg_rotate = new Image()
    @playerimg_rotate.src = @url_rotate
    @background = new Image()
    @background.src = @backgroundurl
    @bullet_url = "./img/serceCzerwone.png"
    @bulletimg = new Image()
    @bulletimg.src = @bullet_url

class angel
  constructor: (id)  ->
    @id = parseInt( id, 10 );


