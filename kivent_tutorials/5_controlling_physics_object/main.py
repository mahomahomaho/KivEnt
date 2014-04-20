from kivy.app import App
from kivy.uix.widget import Widget
from kivy.clock import Clock
from kivy.core.window import Window
import cymunk
import kivent
from random import randint
from math import radians, atan2, degrees
from kivent import GameSystem
from cymunk import PivotJoint, GearJoint, Body
from kivy.properties import NumericProperty, ListProperty
from kivy.vector import Vector


class ShipSystem(GameSystem):

    def collide_with_view(self, space, arbiter):
        gameworld = self.gameworld
        entities = gameworld.entities
        ent1_id = arbiter.shapes[0].body.data
        ent2_id = arbiter.shapes[1].body.data
        ent1 = entities[ent1_id]
        ship_data = ent1.ship
        in_view = ship_data.in_view
        in_view.add(ent2_id)
        return False

    def separate_from_view(self, space, arbiter):
        gameworld = self.gameworld
        entities = gameworld.entities
        ent1_id = arbiter.shapes[0].body.data
        ent2_id = arbiter.shapes[1].body.data
        ent1 = entities[ent1_id]
        ship_data = ent1.ship
        in_view = ship_data.in_view
        in_view.discard(ent2_id)
        return False


class TestGame(Widget):
    current_entity = NumericProperty(None)

    def __init__(self, **kwargs):
        super(TestGame, self).__init__(**kwargs)
        Clock.schedule_once(self.init_game)

    def init_game(self, dt):
        self.setup_map()
        self.setup_states()
        self.set_state()
        self.setup_collision_callbacks()
        self.draw_some_stuff()
        Clock.schedule_interval(self.update, 0)

    def on_touch_down(self, touch):
        gameworld = self.gameworld
        entities = gameworld.entities
        entity = entities[self.current_entity]
        ai_data = entity.steering_ai
        ai_data.target = (touch.x, touch.y)

    def draw_some_stuff(self):
        size = Window.size
        for x in range(1):
            pos = (250, 250)
            ship_id = self.create_ship(pos)
            self.current_entity = ship_id
        for x in range(10):
            pos = randint(0, size[0]), randint(0, size[1])
            self.create_asteroid(pos)


    def no_collide(self, space, arbiter):
        return False

    def setup_collision_callbacks(self):
        systems = self.gameworld.systems
        physics_system = systems['physics']
        ship_system = systems['ship']
        physics_system.add_collision_handler(
            1, 2, 
            begin_func=self.no_collide)
        physics_system.add_collision_handler(
            2, 3, 
            begin_func=ship_system.collide_with_view,
            separate_func=ship_system.separate_from_view)

    def create_asteroid(self, pos):
        x_vel = randint(0, 10)
        y_vel = randint(0, 10)
        angle = radians(randint(-360, 360))
        angular_velocity = radians(randint(-150, -150))
        shape_dict = {'inner_radius': 0, 'outer_radius': 32, 
            'mass': 50, 'offset': (0, 0)}
        col_shape = {'shape_type': 'circle', 'elasticity': .5, 
            'collision_type': 3, 'shape_info': shape_dict, 'friction': 1.0}
        col_shapes = [col_shape]
        physics_component = {'main_shape': 'circle', 
            'velocity': (x_vel, y_vel), 
            'position': pos, 'angle': angle, 
            'angular_velocity': angular_velocity, 
            'vel_limit': 250, 
            'ang_vel_limit': radians(200), 
            'mass': 50, 'col_shapes': col_shapes}
        create_component_dict = {'physics': physics_component, 
            'physics_renderer': {'texture': 'asteroid1', 'size': (64 , 64)}, 
            'position': pos, 'rotate': 0}
        component_order = ['position', 'rotate', 
            'physics', 'physics_renderer']
        return self.gameworld.init_entity(create_component_dict, component_order)

    def create_ship(self, pos):
        x_vel = 0
        y_vel = 0
        angle = 0
        angular_velocity = 0
        view_distance = 200
        view_dict = {'vertices': [(0., 0.), (0, 88.), 
            (view_distance, 108.), (view_distance, -20.)],
            'offset': (96,44.)}
        view_shape_dict = {'shape_type': 'poly', 'elasticity': 0.0, 
            'collision_type':2, 'shape_info': view_dict, 'friction': 0.0}
        shape_dict = {'inner_radius': 0, 'outer_radius': 45, 
            'mass': 10, 'offset': (0, 0)}
        col_shape = {'shape_type': 'circle', 'elasticity': .0, 
            'collision_type': 1, 'shape_info': shape_dict, 'friction': .7}
        col_shapes = [col_shape, view_shape_dict]
        physics_component = {'main_shape': 'circle', 
            'velocity': (x_vel, y_vel), 
            'position': pos, 'angle': angle, 
            'angular_velocity': angular_velocity, 
            'vel_limit': 750, 
            'ang_vel_limit': radians(900), 
            'mass': 50, 'col_shapes': col_shapes}
        steering_component = {
            'turn_speed': 4.0,
            'stability': 600000.0,
            'max_force': 100000.0,
            'speed': 200.,
            }
        steering_ai_component = {
            'avoidance_max': 150.,
            'change_time': 2.0,
            'state': 'Wander'
            }
        ship_component = {'in_view': set()}
        create_component_dict = {'physics': physics_component, 
            'physics_renderer': {'texture': 'ship7', 'size': (96 , 88)}, 
            'position': pos, 'rotate': 0, 'steering': steering_component,
            'steering_ai': steering_ai_component, 'ship': ship_component}
        component_order = ['position', 'rotate', 
            'physics', 'physics_renderer', 'steering', 'steering_ai',
            'ship']
        return self.gameworld.init_entity(create_component_dict, component_order)

    def setup_map(self):
        gameworld = self.gameworld
        gameworld.currentmap = gameworld.systems['map']

    def update(self, dt):
        self.gameworld.update(dt)

    def setup_states(self):
        self.gameworld.add_state(state_name='main', 
            systems_added=['renderer', 'physics_renderer'],
            systems_removed=[], systems_paused=[],
            systems_unpaused=['renderer', 'physics_renderer',
                'steering'],
            screenmanager_screen='main')

    def set_state(self):
        self.gameworld.state = 'main'


class YourAppNameApp(App):
    def build(self):
        Window.clearcolor = (0, 0, 0, 1.)


if __name__ == '__main__':
    YourAppNameApp().run()
