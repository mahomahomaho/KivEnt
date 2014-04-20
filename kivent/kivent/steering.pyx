
from cymunk cimport (GearJoint, PivotJoint, Vec2d, cpVect, cpv, cpvlength,
    cpFloat, cpBool, cpvunrotate, cpvrotate, cpvdot, cpvsub, cpvnear,
    cpvneg, cpvadd, cpvmult, cpvcross, cpvnormalize, cpvdist,
    cpvdistsq)
from libc.math cimport atan2



from random import randint


cdef class SteeringAIComponent:
    cdef float _avoidance_max
    cdef float _attack_angle
    cdef float _decision_time
    cdef float _change_time
    cdef str _state
    cdef tuple _target

    def __cinit__(self, float avoidance_max, float change_time, str state):
        self._avoidance_max = avoidance_max
        self._attack_angle = 0.0
        self._change_time = change_time
        self._decision_time = change_time
        self._state = state
        self._target = (None, None)

    property avoidance_max:
        def __get__(self):
            return self._avoidance_max
        def __set__(self, float value):
            self._avoidance_max = value

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

    property change_time:
        def __get__(self):
            return self._change_time
        def __set__(self, float value):
            self._change_time = value

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
    cdef tuple _target
    cdef float _speed
    cdef bool _active

    def __cinit__(self, Body body, PivotJoint pivot, GearJoint gear,
        float speed):
        self._target = (None, None)
        self._steering_body = body
        self._pivot = pivot
        self._gear = gear
        self._speed = speed
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

    property target:
        def __get__(self):
            return self._target
        def __set__(self, tuple target):
            self._target = target

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

    property speed:
        def __get__(self):
            return self._speed
        def __set__(self, float speed):
            self._speed = speed

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
        change_time = args['change_time']
        state = args['state']
        new_component = SteeringAIComponent.__new__(SteeringAIComponent, 
            avoidance_max, change_time, state)
        return new_component

    def update(self, dt):
        cdef list entity_ids = self.entity_ids
        cdef int entity_id
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef SteeringComponent steering_data
        cdef SteeringAIComponent ai_data
        cdef PhysicsComponent physics_data
        cdef PhysicsComponent obs_physics_data
        cdef str system_id = self.system_id
        cdef str physics_id = self.physics_system
        cdef str steering_id = self.steering_system
        cdef str state
        cdef float speed
        cdef Body body
        cdef str view_id = self.view_system
        cdef set in_view
        cdef cpVect target
        cdef cpVect pos
        cdef cpVect ob_pos
        cdef cpVect ob_vel
        cdef cpVect b_vel
        cdef cpVect ob_vel_t
        cdef cpVect avoid_vec
        cdef cpVect avoid_norm
        cdef float avoid_max
        cdef cpVect new_targ
        cdef cpVect new_av
        cdef Body ob_body
        cdef tuple tup_targ
        execute_decision = self.execute_decision
        for entity_id in entity_ids:
            entity = entities[entity_id]
            steering_data = getattr(entity, steering_id)
            physics_data = getattr(entity, physics_id)
            body = physics_data._body
            ai_data = getattr(entity, system_id)
            ai_data._decision_time += dt
            view_data = getattr(entity, view_id)
            in_view = view_data.in_view
            speed = steering_data._speed
            avoid_max = ai_data._avoidance_max
            state = ai_data._state
            if ai_data._decision_time >= ai_data._change_time:
                #execute_decision(steering_data, ai_data, state)
                ai_data._decision_time = 0.0
            tup_targ = ai_data._target
            avoid_vec = cpv(0., 0.)
            if len(in_view) > 0:
                for obstacle_id in in_view:
                    print obstacle_id
                    ob_ent = entities[obstacle_id]
                    obs_physics_data = getattr(ob_ent, physics_id)
                    ob_body = obs_physics_data._body
                    ob_pos = ob_body._body.p
                    ob_vel = ob_body._body.v
                    ob_vel_t = cpvmult(ob_vel, dt)
                    ob_av = cpvadd(ob_pos, ob_vel_t)
                    avoid_vec = cpvadd(ob_av, avoid_vec)
                try:
                    target = cpv(tup_targ[0], tup_targ[1])
                    avoid_norm = cpvnormalize(avoid_vec)
                    print avoid_norm
                    print avoid_max
                    new_av = cpvmult(avoid_norm, avoid_max)
                    print new_av
                    new_targ = cpvsub(target, new_av)
                    tup_targ = new_targ.x, new_targ.y
                except:
                    pass
            print tup_targ
            steering_data._target = tup_targ


    def execute_decision(self, SteeringComponent steering_data, 
        SteeringAIComponent ai_data, str state):
        if state == 'Wander':
            self.choose_random_position(ai_data)

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
        cdef float speed = args['speed']
        new_component = SteeringComponent.__new__(SteeringComponent, 
            body, pivot, gear, speed)
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
        new_args = {'body': steering_body, 'pivot': pivot, 'gear': gear,
            'speed': args['speed']}
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
        cdef str physics_id = self.physics_system
        cdef SteeringComponent steering_data
        cdef PhysicsComponent physics_data
        cdef Body body
        cdef Body steering_body
        cdef float angle
        cdef cpVect v1
        cdef cpVect target
        cdef tuple target_pos
        cdef cpVect move_delta
        cdef float turn
        cdef tuple velocity_rot
        cdef float speed
        cdef cpVect unrot
        cdef float x, y
        cdef bool solve

        for entity_id in entity_ids:
            entity = entities[entity_id]
            steering_data = getattr(entity, system_id)
            physics_data = getattr(entity, physics_id)
            if steering_data._active:
                body = physics_data._body
                target_pos = steering_data._target
                steering_body = steering_data._steering_body
                try:
                    x, y = target_pos
                except:
                    steering_body.velocity = (0., 0.)
                    continue
                target = cpv(x, y)
                body_pos = body._body.p
                v1 = body._body.rot
                angle = body.angle
                speed = steering_data._speed
                move_delta = cpvsub(target, body_pos)
                unrot = cpvunrotate(v1, move_delta)
                turn = atan2(unrot.y, unrot.x)
                steering_body.angle = angle - turn
                if cpvnear(target, body_pos, 75.0):
                    velocity_rot = (0., 0.)
                elif turn <= -1.3 or turn >= 1.3:
                    velocity_rot = (0., 0.)
                else:
                    new_vec = cpvrotate(v1, cpv(speed, 0.0))  
                    velocity_rot = (new_vec.x, new_vec.y)
                steering_body.velocity = velocity_rot
