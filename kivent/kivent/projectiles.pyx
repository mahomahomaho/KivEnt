from kivy.clock import Clock
from functools import partial


cdef class ProjectileEmitterConfig:
    cdef float _muzzle_impulse
    cdef float _muzzle_force
    cdef int _projectile_count
    cdef float _rate_of_fire
    cdef int _clip_size
    cdef float _reload_time

    def __cinit__(self, float muzzle_impulse, float muzzle_force,
        int projectile_count, float rate_of_fire, int clip_size, 
        float reload_time):

        self._muzzle_impulse = muzzle_impulse
        self._muzzle_force = muzzle_force
        self._projectile_count = projectile_count
        self._rate_of_fire = rate_of_fire
        self._clip_size = clip_size
        self._reload_time = reload_time


cdef class ProjectileConfig:
    cdef float _width
    cdef float _height
    cdef float _mass
    cdef float _damage
    cdef float _max_speed
    cdef float _max_ang_speed
    cdef dict _effects
    cdef str _sound
    cdef str _texture
    cdef str _ptype
    cdef float _lifespan

    def __cinit__(self, float width, float height, float mass, float damage,
        float max_speed, float max_ang_speed, dict effects, str sound, 
        str ptype, str texture, float lifespan):

        self._width = width
        self._height = height
        self._mass = mass
        self._damage = damage
        self._max_speed = max_speed
        self._max_ang_speed = max_ang_speed
        self._effects = effects
        self._ptype = ptype
        self._sound = sound
        self._texture = texture
        self._lifespan = lifespan


cdef class ProjectileEmitterComponent:
    cdef list _offsets
    cdef list _ptype
    cdef bool _reloading
    cdef float _current_time
    cdef bool _can_fire
    cdef dict _ammo
    cdef int _current_clip
    cdef int parent
    cdef ProjectileEmitterConfig _config

    def __cinit__(self, list offsets, list types,
        str current_type, ProjectileEmitterConfig config,
        dict ammo_counts, int parent):

        self._offsets = offsets
        self._ptypes = types
        self._current_type = current_type
        self._current_time = 0.0
        self._can_fire = False
        self._reloading = True
        self._config = config
        self._ammo_counts = ammo_counts
        self._current_clip = 0.0
        self._parent = parent


cdef class ProjectileComponent:
    cdef float _lifespan
    cdef list _effects
    cdef str _ptype
    cdef float _current_time
    cdef ProjectileConfig _config
    
    def __cinit__(self, ProjectileConfig config):
        self._effects = []
        self._lifespan = config._life_span
        self._current_time = 0.0
        self._ptype = config._ptype
        self._config = config

    property damage:
        def __get__(self):
            return self._config._damage

    property max_speed:
        def __get__(self):
            return self._config._max_speed

    property lifespan:
        def __get__(self):
            return self._lifespan
        def __set__(self, float value):
            self._lifespan = value

    property effects:
        def __get__(self):
            return self._effects
        def __set__(self, list value):
            self._effects = value

    property current_time:
        def __get__(self):
            return self._current_time
        def __set__(self, float value):
            self._current_time = value


class ProjectileEmitterSystem(GameSystem):
    physics_system = StringProperty(None)


    def __init__(self, **kwargs):
        super(ProjectileEmitterSystem, self).__init__(**kwargs)
        self.fire_events = []
        self.setup_projectiles_dicts()

    def add_fire_event(self, int entity_id):
        self.fire_events.append(entity_id)

    def generate_component(self, dict args):
        offsets = args['offsets']
        barrel_count = args['barrel_count']
        types = args['types']
        current_type = args['current_type']
        new_component = ProjectileEmitterComponent.__new__(
            ProjectileEmitterComponent, offsets, barrel_count, types,
            current_type)
        return new_component

    def spawn_projectile_with_dict(self, tuple location, float angle, 
        int collision_type, ProjectileConfig config):
        cdef object gameworld = self.gameworld
        init_entity = gameworld.init_entity
        cdef list entities = gameworld.entities
        cdef float width = config._width
        cdef float height = config._height
        cdef float mass = config._mass
        cdef float max_speed = config._max_speed
        cdef float max_ang_speed = config._max_ang_speed
        cdef str texture = config._texture
        cdef str ptype = config._type
        cdef float lifespan = config._lifespan
        cdef dict effects = config._effects
        cdef dict projectile_box_dict = {
            'width': width, 
            'height': height, 
            'mass': mass}
        cdef dict projectile_col_shape_dict = {
            'shape_type': 'box', 'elasticity': 1.0, 
            'collision_type': collision_type, 
            'shape_info': projectile_box_dict, 
            'friction': .3}
        cdef dict projectile_physics_component_dict = { 
            'main_shape': 'box', 
            'velocity': (0, 0), 
            'position': location, 
            'angle': angle, 
            'angular_velocity': 0, 
            'mass': mass, 
            'vel_limit': max_speed, 
            'ang_vel_limit': keRadians(max_ang_speed),
            'col_shapes': [projectile_col_shape_dict]}
        cdef dict projectile_renderer_dict = {
            'texture': texture, 
            'size': (width, height)}
        cdef dict create_projectile_dict = {
            'position': location,
            'rotate': angle,
            'cymunk_physics': projectile_physics_component_dict, 
            'physics_renderer': projectile_renderer_dict, 
            'projectile_system': (lifespan, config)}
        cdef list component_order = ['position', 'rotate', 'cymunk_physics', 
            'physics_renderer', 'projectile_system']
        cdef int bullet_ent_id = init_entity(
            create_projectile_dict, component_order)
        cdef ProjectileComponent projectile_system_data = entities[
            bullet_ent_id].projectile_system
        cdef ParticleComponent particle_comp
        if 'engine' in effects:
            particle_system1 = {'particle_file': effects['engine'], 
                'offset': height*.5, 
                'parent': bullet_ent_id}
            p_ent = init_entity(
                {'particles': particle_system1}, ['particles'])
            particle_comp = entities[p_ent].particles
            particle_comp._system_on = True
            projectile_system_data._effects['engine'] = p_ent
        if 'explosion' in effects:
            particle_system2 = {'particle_file': effects['explosion'], 
                'offset': 0, 'parent': bullet_ent_id}
            p_ent2 = init_entity(
                {'particles': particle_system2}, ['particles'])
            projectile_system_data._effects['explosion'] = p_ent2
        return bullet_ent_id

    def load_data_from_json(self):
        json_file = self.json_file
        cdef dict data = self.data
        cdef float muzzle_impulse, 
        cdef float muzzle_force,
        cdef int projectile_count, 
        cdef float rate_of_fire, 
        cdef int clip_size, 
        cdef float reload_time, 
        cdef str projectile_type
        try:
            json = JsonStore(json_file)
        except:
            return
        for each in json:
            json_data = json[each]
            muzzle_impulse = json_data['muzzle_impulse']
            muzzle_force = json_data['muzzle_force']
            projectile_count = json_data['projectile_count']
            rate_of_fire = json_data['rate_of_fire']
            clip_size = json_data['clip_size']
            reload_time = json_data['reload_time']
            data[each] = ProjectileEmitterConfig.__new__(
                ProjectileEmitterConfig, muzzle_impulse, muzzle_force,
                projectile_count, rate_of_fire, clip_size, reload_time)

    def fire_projectile(self, entity_id):
        entities = self.gameworld.entities
        bullet = entities[entity_id]
        physics_data = bullet.cymunk_physics
        unit_vector = physics_data.unit_vector
        projectile_system = bullet.projectile_system
        bullet_accel = projectile_system.accel
        force = bullet_accel*unit_vector[0], bullet_accel*unit_vector[1]
        force_offset = -unit_vector[0], -unit_vector[1]
        bullet_body = bullet.cymunk_physics.body
        bullet_body.apply_impulse(force, force_offset)
        if len(projectile_system.linked) > 0:
            bullet_body.apply_force(force, force_offset)
            engine_effect = entities[projectile_system.linked[0]].particles
            engine_effect.system_on = True

    def update(self, dt):
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef int entity_id
        cdef list fire_events = self.fire_events
        cdef list entity_ids = self.entity_ids
        cdef object entity
        cdef str system_id = self.system_id
        cdef ProjectileEmitterConfig config
        cdef ProjectileEmitterComponent p_emitter_comp
        cdef float c_time
        cdef bool can_fire
        cdef bool reloading
        cdef float rof
        cdef float reload_time

        for entity_id in entity_ids:
            entity = entities[entity_id]
            p_emitter_comp = getattr(entity, system_id)
            config = p_emitter_comp._config
            reloading = p_emitter_comp._reloading
            can_fire = p_emitter_comp._can_fire
            if reloading or not can_fire:
                p_emitter_comp._current_time += dt
            c_time = p_emitter_comp._current_time
            rof = config._rate_of_fire
            reload_time = config._reload_time
            if reloading and c_time > reload_time:
                p_emitter_comp._reloading = reloading = False
                p_emitter_comp._current_time = 0.0
            elif not can_fire and c_time > rof:
                p_emitter_comp._can_fire = can_fire = True
                p_emitter_comp._current_time = 0.0

            if can_fire and not reloading and entity_id in fire_events:
                pass
                #do fire gun

        self.fire_events = []


        for i in xrange(num_events):
            entity_id = fe_p(0)
            character = entities[entity_id]
            is_character = False
            if entity_id == player_character_system.current_character_id:
                is_character = True
            ship_system_data = character.ship_system
            current_projectile_type = ship_system_data.current_projectile_type
            current_bullet_ammo = ship_system_data.current_bullet_ammo
            current_rocket_ammo = ship_system_data.current_rocket_ammo
            projectile_type = ship_system_data.projectile_type + current_projectile_type
            projectile = projectiles_dict[projectile_type]
            projectile_width = projectile['width']
            projectile_height = projectile['height']
            character_physics = character.cymunk_physics
            character_position = character.position
            hard_points = ship_system_data.hard_points
            number_of_shots = len(hard_points)
            if ((current_projectile_type == '_bullet' and 
                 current_bullet_ammo - number_of_shots >= 0) or 
                (current_projectile_type == '_rocket' and 
                current_rocket_ammo - number_of_shots >= 0)):
                for hard_point in hard_points:
                    position_offset = (
                        hard_point[0], hard_point[1] + projectile_height*.5)
                    angle = character_physics.body.angle
                    x, y = position_offset
                    position_offset_rotated = get_rotated_vector(
                        angle, x, y
                        )
                    location = (
                        character_position._x + position_offset_rotated[0],
                        character_position._y + position_offset_rotated[1])
                    bullet_ent_id = spawn_proj(
                        location, angle, ship_system_data.color, 
                        projectiles_dict[projectile_type])
                    fire_projectile(bullet_ent_id)
                if current_projectile_type == '_bullet':
                    ship_system_data.current_bullet_ammo -= number_of_shots
                    c_once(partial(sound_system.schedule_play, 'bulletfire'))  
                if current_projectile_type == '_rocket':
                    ship_system_data.current_rocket_ammo -= number_of_shots
                    c_once(partial(sound_system.schedule_play, 'rocketfire'))
                if is_character:
                    player_character_system.current_bullet_ammo = ship_system_data.current_bullet_ammo
                    player_character_system.current_rocket_ammo = ship_system_data.current_rocket_ammo


class ProjectileSystem(GameSystem):
    bullet_collision_type = NumericProperty(None)
    types_to_collide = ListProperty([])
    types_to_ignore = ListProperty([])
    sound_system = StringProperty(None)
    collision_callback = ObjectProperty(None)
    bullet_to_bullet_callback = ObjectProperty(None)

    def __init__(self, **kwargs):
        super(ProjectileSystem, self).__init__(**kwargs)

    def load_data_from_json(self):
        json_file = self.json_file
        cdef dict data = self.data
        cdef float width
        cdef float height
        cdef float mass
        cdef float damage
        cdef float max_speed
        cdef float max_ang_speed
        cdef dict effects
        cdef str sound
        cdef str ptype
        cdef str texture
        try:
            json = JsonStore(json_file)
        except:
            return
        for each in json:
            json_data = json[each]
            width = json_data['width']
            height = json_data['height']
            mass = json_data['mass']
            damage = json_data['damage']
            max_speed = json_data['max_speed']
            max_ang_speed = json_data['max_ang_speed']
            effects = json_data['effects']
            sound = json_data['sound']
            ptype = json_data['type']
            texture = json_data['texture']
            lifespan = json_data['lifespan']
            data[each] = ProjectileConfig.__new__(ProjectileConfig, 
                width, height, mass, damage, max_speed, max_ang_speed, 
                effects, sound, ptype, texture)

    def update(self, dt):
        cdef int entity_id
        cdef object gameworld = self.gameworld
        cdef list entity_ids = self.entity_ids
        cdef list entities = gameworld.entities
        cdef object entity
        cdef ProjectileComponent projectile_system
        cdef float lifespan
        c_once = Clock.schedule_once
        timed_remove_entity = self.timed_remove_entity
        for entity_id in entity_ids:
            entity = entities[entity_id]
            projectile_system = entity.projectile_system
            lifespan = projectile_system._lifespan
            if lifespan > 0:
                projectile_system._current_time += dt
                if projectile_system._current_time >= lifespan:
                    c_once(partial(timed_remove_entity, entity_id))
  
    def remove_entity(self, int entity_id):
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef object entity = entities[entity_id]
        cdef ProjectileComponent projectile_system = entity.projectile_system
        cdef dict effects = entity.projectile_system._effects
        remove_entity = gameworld.remove_entity
        for each in effects:
            remove_entity(effects[each])
        super(ProjectileSystem, self).remove_entity(entity_id)

    def create_rocket_explosion(self, entity_id):
        gameworld = self.gameworld
        entities = gameworld.entities
        entity = entities[entity_id]
        entity.physics_renderer.render = False
        entity.cymunk_physics.body.velocity = (0, 0)
        entity.cymunk_physics.body.reset_forces()
        projectile_data = entity.projectile_system
        linked = projectile_data.linked
        engine_effect_id = linked[0]
        explosion_effect_id = linked[1]
        engine_effect = entities[engine_effect_id].particles
        explosion_effect = entities[explosion_effect_id].particles
        engine_effect.system_on = False
        explosion_effect.system_on = True
        if entity.physics_renderer.on_screen:
            sound_system = gameworld.systems['sound_system']
            Clock.schedule_once(partial(
                sound_system.schedule_play, 'rocketexplosion'))
        projectile_data.armed = False
        Clock.schedule_once(partial(
            gameworld.timed_remove_entity, entity_id), 2.0)

    def spawn_projectile(self, projectile_type, location, angle, color):
        bullet_ent_id = self.spawn_projectile_with_dict(
            location, angle, color, 
            self.projectiles_dict[projectile_type])
        self.fire_projectile(bullet_ent_id)

    def generate_component(self, tuple projectile_args):
        #(float damage, bool armed, float life_span,
        #ProjectileConfig config)
        cdef ProjectileConfig config = self.data[projectile_args[3]]
        new_component = ProjectileComponent.__new__(ProjectileComponent, 
            projectile_args[0], projectile_args[1], projectile_args[2], 
            config)
        return new_component


    def set_armed(self, entity_id, dt):
        entities = self.gameworld.entities
        bullet = entities[entity_id]
        if hasattr(bullet, 'projectile_system'):
            bullet.projectile_system.armed = True

    

    def add_collision_callback(self, type_a, type_b, callback):
        pass


    def clear_projectiles(self):
        for entity_id in self.entity_ids:
            Clock.schedule_once(
                partial(self.gameworld.timed_remove_entity, entity_id))

    def collision_solve_asteroid_bullet(self, space, arbiter):
        gameworld = self.gameworld
        systems = gameworld.systems
        entities = gameworld.entities
        bullet_id = arbiter.shapes[1].body.data
        asteroid_id = arbiter.shapes[0].body.data
        bullet = entities[bullet_id]
        projectile_system = bullet.projectile_system
        if projectile_system.armed:
            bullet_damage = projectile_system.damage
            systems['asteroid_system'].damage(asteroid_id, bullet_damage)
            if len(projectile_system.linked) > 0:
                self.create_rocket_explosion(bullet_id)
            else:
                projectile_system.armed = False
                Clock.schedule_once(
                    partial(gameworld.timed_remove_entity, bullet_id))
            return True
        else:
            return False

    def collision_solve_bullet_bullet(self, space, arbiter):
        bullet_id2 = arbiter.shapes[1].body.data
        bullet_id1 = arbiter.shapes[0].body.data
        gameworld = self.gameworld
        entities = gameworld.entities
        bullet1 = entities[bullet_id1]
        proj1_s = bullet1.projectile_system
        bullet2 = entities[bullet_id2]
        proj2_s = bullet2.projectile_system
        if proj1_s.armed and proj2_s.armed:
            if len(proj1_s.linked) > 0:
                self.create_rocket_explosion(bullet_id1)
            else:
                proj1_s.armed = False
                Clock.schedule_once(
                    partial(gameworld.timed_remove_entity, bullet_id1))
            if len(proj2_s.linked) > 0:
                self.create_rocket_explosion(bullet_id2)
            else:
                proj2_s.armed = False
                Clock.schedule_once(
                    partial(gameworld.timed_remove_entity, bullet_id2))

    def collision_begin_ship_bullet(self, space, arbiter):
        gameworld = self.gameworld
        systems = gameworld.systems
        entities = gameworld.entities
        sound_system = systems['sound_system']
        bullet_id = arbiter.shapes[1].body.data
        character_id = systems['player_character'].current_character_id
        ship_id = arbiter.shapes[0].body.data
        bullet = entities[bullet_id]
        if bullet.projectile_system.armed:
            if character_id == ship_id:
                Clock.schedule_once(partial(
                    sound_system.schedule_play, 'shiphitbybullet'))
            return True
        else:
            return False

    def collision_begin_bullet_bullet(self, space, arbiter):
        gameworld = self.gameworld
        entities = gameworld.entities
        bullet_id2 = arbiter.shapes[1].body.data
        bullet_id1 = arbiter.shapes[0].body.data
        bullet1 = entities[bullet_id1]
        bullet2 = entities[bullet_id2]
        if bullet1.projectile_system.armed and bullet2.projectile_system.armed:
            if bullet1.physics_renderer.on_screen or bullet2.physics_renderer.on_screen:
                sound_system = gameworld.systems['sound_system']
                Clock.schedule_once(partial(sound_system.schedule_play, 'bullethitbullet'))
            return True
        else:
            return False

    def collision_begin_asteroid_bullet(self, space, arbiter):
        gameworld = self.gameworld
        entities = gameworld.entities
        bullet_id = arbiter.shapes[1].body.data
        asteroid_id = arbiter.shapes[0].body.data
        bullet = entities[bullet_id]
        if bullet.projectile_system.armed:
            if bullet.physics_renderer.on_screen:
                sound_system = gameworld.systems['sound_system']
                Clock.schedule_once(
                    partial(sound_system.schedule_play, 'bullethitasteroid'))
            return True
        else:
            return False

    def collision_solve_ship_bullet(self, space, arbiter):
        gameworld = self.gameworld
        systems = gameworld.systems
        entities = gameworld.entities
        bullet_id = arbiter.shapes[1].body.data
        ship_id = arbiter.shapes[0].body.data
        bullet = entities[bullet_id]
        projectile_system = bullet.projectile_system
        if projectile_system.armed:
            bullet_damage = bullet.projectile_system.damage
            systems['ship_system'].damage(ship_id, bullet_damage)
            if len(projectile_system.linked) > 0:
                self.create_rocket_explosion(bullet_id)
            else:
                projectile_system.armed = False
                Clock.schedule_once(
                    partial(gameworld.timed_remove_entity, bullet_id))
            return True
        else:
            print 'collision with bullet after explosion'
            return False