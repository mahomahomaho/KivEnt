from cymunk cimport (GearJoint, PivotJoint, Vec2d, cpVect, cpv, cpvlength,
    cpFloat, cpBool, cpvunrotate, cpvrotate, cpvdot, cpvsub, cpvnear,
    cpvneg, cpvadd, cpvmult, cpvcross, cpvnormalize, cpvdist,
    cpvdistsq, cpvperp, cpvrperp)
from libc.math cimport atan2, fabs
from random import randint
from operator import itemgetter


cdef class SteeringAIComponent:
    cdef float _avoidance_max
    cdef float _speed_max
    cdef float _attack_angle
    cdef float _decision_time
    cdef float _current_time
    cdef str _state
    cdef tuple _target
    cdef float _distance_tolerance
    cdef float _angle_tolerance

    def __cinit__(self, float speed, float avoidance_max, float decision_time, 
        str state):
        self._avoidance_max = avoidance_max
        self._speed_max = speed
        self._attack_angle = 0.0
        self._current_time = decision_time
        self._decision_time = decision_time
        self._state = state
        self._target = (None, None)
        self._distance_tolerance = 55.0
        self._angle_tolerance = 1.4

    property avoidance_max:
        def __get__(self):
            return self._avoidance_max
        def __set__(self, float value):
            self._avoidance_max = value

    property speed_max:
        def __get__(self):
            return self._speed_max
        def __set__(self, float value):
            self._speed_max = value

    property decision_time:
        def __get__(self):
            return self._decision_time
        def __set__(self, float value):
            self._decision_time = value

    property attack_angle:
        def __get__(self):
            return self._attack_angle
        def __set__(self, float value):
            self._attack_angle = value

    property current_time:
        def __get__(self):
            return self._current_time
        def __set__(self, float value):
            self._current_time = value

    property state:
        def __get__(self):
            return self._state
        def __set__(self, str value):
            self._state = value

    property target:
        def __get__(self):
            return self._target
        def __set__(self, tuple target):
            self._target = target


cdef class SteeringComponent: 
    cdef Body _steering_body
    cdef PivotJoint _pivot
    cdef GearJoint _gear
    cdef cpVect _velocity
    cdef float _angle
    cdef bool _active

    def __cinit__(self, Body body, PivotJoint pivot, GearJoint gear):
        self._velocity = cpv(0.0, 0.0)
        self._steering_body = body
        self._angle = 0.0
        self._pivot = pivot
        self._gear = gear
        self._active = True

    property steering_body:
        def __get__(self):
            return self._steering_body
        def __set__(self, Body body):
            self._steering_body = body

    property pivot:
        def __get__(self):
            return self._pivot
        def __set__(self, PivotJoint pivot):
            self._pivot = pivot

    property gear:
        def __get__(self):
            return self._gear
        def __set__(self, GearJoint gear):
            self._gear = gear

    property angle:
        def __get__(self):
            return self._angle
        def __set__(self, float angle):
            self._angle = angle

    property velocity:
        def __get__(self):
            cdef cpVect _vel = self._velocity
            return Vec2d(_vel.x, _vel.y)
        def __set__(self, tuple new_vel):
            self._velocity = cpv(new_vel[0], new_vel[1])

    property turn_speed:
        def __get__(self):
            return self._gear.max_bias
        def __set__(self, float turn_speed):
            self._gear.max_bias = turn_speed

    property active:
        def __get__(self):
            return self._active
        def __set__(self, bool new):
            self._active = new

    property stability:
        def __get__(self):
            return self._gear.max_force
        def __set__(self, float stability):
            self._gear.max_force = stability

    property max_force:
        def __get__(self):
            return self._pivot.max_force
        def __set__(self, float force):
            self._pivot.max_force = force


class SteeringAISystem(GameSystem):
    physics_system = StringProperty(None)
    steering_system = StringProperty(None)
    updateable = BooleanProperty(True)
    view_system = StringProperty(None)

    def generate_component(self, dict args):
        avoidance_max = args['avoidance_max']
        decision_time = args['decision_time']
        state = args['state']
        speed = args['speed']
        new_component = SteeringAIComponent.__new__(SteeringAIComponent, 
            speed, avoidance_max, decision_time, state)
        return new_component

    def update(self, dt):
        cdef list entity_ids = self.entity_ids
        cdef int entity_id
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        execute_decision = self.execute_decision

        cdef str system_id = self.system_id
        cdef str physics_id = self.physics_system
        cdef str steering_id = self.steering_system
        cdef str view_id = self.view_system
        cdef SteeringComponent steering_data
        cdef SteeringAIComponent ai_data
        cdef PhysicsComponent physics_data
        cdef Body body
        cdef object entity

        for entity_id in entity_ids:
            entity = entities[entity_id]
            ai_data = getattr(entity, system_id)
            ai_data._current_time += dt
            state = ai_data._state
            if ai_data._current_time >= ai_data._decision_time:
                steering_data = getattr(entity, steering_id)
                physics_data = getattr(entity, physics_id)
                view_data = getattr(entity, view_id)
                execute_decision(physics_data, steering_data, ai_data, 
                    view_data, state)
                ai_data._current_time = 0.0

    def avoid_obstacles(self, PhysicsComponent physics_data, 
        SteeringAIComponent ai_data, SteeringComponent steering_data,
        object view_data):
        cdef tuple target_tup = ai_data._target
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef str physics_id = self.physics_system
        cdef object entity
        cdef PhysicsComponent view_physics_data
        cdef float x, y
        cdef Body body = physics_data._body
        cdef Body view_body
        cdef cpVect view_pos
        cdef cpVect target
        cdef int view_id
        cdef dict avoid_dict
        cdef cpVect avoid_vec
        cdef float max_avoid = ai_data._avoidance_max
        try:
            x, y = target_tup
            target = cpv(x, y)
        except:
            return cpv(0., 0.)
        cdef cpVect b_pos = body._body.p
        cdef cpVect b_vel = body._body.v
        cdef cpVect avoid_tot = cpv(0., 0.)
        cdef set in_view = view_data.in_view
        cdef float dist
        cdef float scaling_factor
        cdef float view_distance = view_data.view_distance
        cdef cpVect center_vec = cpvadd(
            b_pos, cpvmult(cpvnormalize(b_vel), view_distance))
        for view_id in in_view:
            entity = entities[view_id]
            view_physics_data = getattr(entity, physics_id)
            view_body = view_physics_data._body
            view_pos = view_body._body.p
            avoid_vec = cpvsub(center_vec, view_pos)
            dist = cpvdist(view_pos, b_pos)
            scaling_factor = view_distance / dist
            avoid_tot = cpvadd(avoid_tot, cpvmult(avoid_vec, scaling_factor))
        return cpvmult(cpvnormalize(avoid_tot), max_avoid)

    def calculate_desired_velocity(self, Body body, 
        SteeringAIComponent ai_data, float turn):
        cdef tuple target_tup = ai_data._target
        cdef float x, y
        cdef cpVect target
        cdef cpVect b_pos = body._body.p
        cdef float speed = ai_data._speed_max
        cdef float dist_tolerance = ai_data._distance_tolerance
        cdef float ang_tolerance = ai_data._angle_tolerance
        cdef cpVect desired_velocity
        cdef cpVect current_vel
        try:
            x, y = target_tup
            target = cpv(x, y)
        except:
            return cpv(0., 0.)
        if cpvnear(target, b_pos, dist_tolerance):
            return cpv(0., 0.)
        elif fabs(turn) > ang_tolerance:
            return cpv(0., 0.)
        else:
            desired_velocity = cpvmult(
                cpvnormalize(cpvsub(target, b_pos)), speed)
            return desired_velocity

    def calculate_angle(self, Body body, SteeringAIComponent ai_data,
        SteeringComponent steering_data):
        cdef float angle = body._body.a
        cdef tuple target_tup = ai_data._target
        cdef float x, y
        cdef cpVect target
        cdef cpVect b_pos = body._body.p
        cdef cpVect unit_vector = body._body.rot
        cdef float dist_tolerance = ai_data._distance_tolerance
        try:
            x, y = target_tup
            target = cpv(x, y)
        except:
            return 0.0
        if cpvnear(target, b_pos, dist_tolerance):
            return 0.0
        cdef cpVect move_delta = cpvsub(target, b_pos)
        cdef cpVect unrot = cpvunrotate(unit_vector, move_delta)
        cdef float turn = atan2(unrot.y, unrot.x)
        cdef float new_angle = angle - turn
        steering_data._angle = new_angle
        return turn

    def calculate_reckless_move(self, Body body, SteeringAIComponent ai_data,
        SteeringComponent steering_data, float turn):
        cdef tuple target_tup = ai_data._target
        cdef float x, y
        cdef cpVect target
        cdef cpVect b_pos = body._body.p
        cdef float dist_tolerance = ai_data._distance_tolerance
        cdef float ang_tolerance = ai_data._angle_tolerance
        cdef cpVect unit_vector = body._body.rot
        cdef float speed = ai_data._speed_max
        try:
            x, y = target_tup
            target = cpv(x, y)
        except:
            steering_data._velocity = cpv(0., 0.)
            return
        if cpvnear(target, b_pos, dist_tolerance):
            steering_data._velocity = cpv(0., 0.)
        elif fabs(turn) > ang_tolerance:
            steering_data._velocity = cpv(0., 0.)
        else:
            steering_data._velocity = cpvrotate(unit_vector, cpv(speed, 0.0))  

    def execute_decision(self, PhysicsComponent physics_data, 
        SteeringComponent steering_data, 
        SteeringAIComponent ai_data, object view_data, str state):
        cdef Body body = physics_data._body
        cdef cpVect avoid 
        cdef cpVect desired
        if state == 'Wander':
            #self.choose_random_position(ai_data)
            turn = self.calculate_angle(body, ai_data, steering_data)
            desired = self.calculate_desired_velocity(body, ai_data, turn)
            avoid = self.avoid_obstacles(physics_data, ai_data, steering_data,
                view_data)
            steering_data._velocity = cpvadd(desired, avoid)
        elif state == 'Reckless':
            turn = self.calculate_angle(body, ai_data, steering_data)
            self.calculate_reckless_move(body, ai_data, steering_data, turn)

    def choose_random_position(self, SteeringAIComponent ai_data):
        cdef object gameworld = self.gameworld
        map_size = gameworld.currentmap.map_size
        cdef tuple new_position =  (randint(0, map_size[0]), 
            randint(0, map_size[1]))
        ai_data._target = new_position


class SteeringSystem(GameSystem):
    physics_system = StringProperty(None)
    updateable = BooleanProperty(True)

    def generate_component(self, dict args):
        cdef Body body = args['body']
        cdef PivotJoint pivot = args['pivot']
        cdef GearJoint gear = args['gear']
        new_component = SteeringComponent.__new__(SteeringComponent, 
            body, pivot, gear)
        return new_component

    def create_component(self, object entity, dict args):
        cdef object gameworld = self.gameworld
        cdef dict systems = gameworld.systems
        cdef str physics_id = self.physics_system
        cdef object physics_system = systems[physics_id]
        cdef Body steering_body = Body(None, None)
        cdef PhysicsComponent physics_data = getattr(entity, physics_id)
        cdef Body body = physics_data.body
        cdef PivotJoint pivot = PivotJoint(steering_body, body, (0, 0), (0, 0))
        cdef GearJoint gear = GearJoint(steering_body, body, 0.0, 1.0)
        gear.error_bias = 0.
        pivot.max_bias = 0.0
        pivot.error_bias = 0.
        gear.max_bias = args['turn_speed']
        gear.max_force = args['stability']
        pivot.max_force = args['max_force']
        cdef Space space = physics_system.space
        space.add(pivot)
        space.add(gear)
        new_args = {'body': steering_body, 'pivot': pivot, 'gear': gear}
        super(SteeringSystem, self).create_component(entity, new_args)

    def remove_entity(self, int entity_id):
        cdef str system_id = self.system_id
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef object entity = entities[entity_id]
        cdef SteeringComponent steering_data = getattr(entity, system_id)
        cdef str physics_id = self.physics_system
        cdef object physics_system = gameworld.systems[physics_id]
        cdef Space space = physics_system.space
        space.remove(steering_data._gear)
        space.remove(steering_data._pivot)
        super(SteeringSystem, self).remove_entity(entity_id)
        
    def update(self, dt):
        cdef list entity_ids = self.entity_ids
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef int entity_id
        cdef str system_id = self.system_id
        cdef SteeringComponent steering_data
        cdef Body steering_body
        for entity_id in entity_ids:
            entity = entities[entity_id]
            steering_data = getattr(entity, system_id)
            if steering_data._active:
                steering_body = steering_data._steering_body
                steering_body._body.v = steering_data._velocity
                steering_body.angle = steering_data._angle
