function love.conf(t)
    t.title = 'Hind Map Test'
    t.author = 'K&D'        	
    t.url = 'www.hind.com'
    t.identity = 'hind_save'
    t.version = '0.8.0'         
    t.console = true           
    t.release = false           	
    t.screen.width = 1200
    t.screen.height = 675
    t.screen.fullscreen = false 
    t.screen.vsync = false
    t.screen.fsaa = 4
    t.modules.joystick = true   
    t.modules.audio = true      
    t.modules.keyboard = true   
    t.modules.event = true      
    t.modules.image = true      
    t.modules.graphics = true   
    t.modules.timer = true      
    t.modules.mouse = true      
    t.modules.sound = true      
    t.modules.physics = true    
end