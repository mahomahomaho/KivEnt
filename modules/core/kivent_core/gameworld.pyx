# cython: profile=True
# cython: embedsignature=True
from kivy.uix.widget import Widget, WidgetException
from kivy.properties import (StringProperty, ListProperty, NumericProperty, 
DictProperty, BooleanProperty, ObjectProperty)
from kivy.clock import Clock
from functools import partial
from kivy.graphics import RenderContext
from kivent_core.systems.gamesystem cimport GameSystem
from kivent_core.systems.position_systems cimport PositionSystem2D
from kivent_core.uix.cwidget cimport CWidget
from kivent_core.entity cimport Entity
from kivent_core.managers.entity_manager cimport EntityManager
from kivent_core.managers.system_manager cimport (SystemManager, 
    DEFAULT_SYSTEM_COUNT, DEFAULT_COUNT)
from kivent_core.memory_handlers.membuffer cimport Buffer
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.memory_handlers.utils cimport memrange
from kivent_core.rendering.vertex_formats cimport (format_registrar, 
    FormatConfig)
from kivent_core.managers.resource_managers cimport ModelManager
from kivy.logger import Logger
debug = False

def test_gameworld():

    gameworld = GameWorld()
    gameworld.zones = {'test': 1000, 'general': 1000, 'test2': 1000}
    pos_system = PositionSystem2D()
    pos_system.system_id = 'position'
    pos_system.zones = ['test', 'general']
    gameworld.add_system(pos_system)
    gameworld.allocate()
    entity = gameworld.entities[0]
    init_entity = gameworld.init_entity
    for x in range(150):
        component_list = ['position']
        creation_dict = {'position': (10., 10.)}
        print('making entity', x)
        ent_id = init_entity(creation_dict, component_list)
        print(ent_id)
    for entity in memrange(gameworld.entities):
        print(entity.entity_id, entity.position.x, entity.position.y)


class GameWorldOutOfSpaceError(Exception):
    pass


class GameWorld(Widget):
    '''GameWorld is the manager of all Entities and GameSystems in your Game.
    It will be responsible for initializing and removing entities, as well as
    managing which GameSystems are added, removed, and paused.

    **Attributes:**
        **state** (StringProperty): State is a string property that corresponds 
        to the current state for your application in the states dict. It will 
        control the current screen of the gamescreenmanager, as well as which 
        systems are currently added or removed from canvas or paused.

        **number_entities** (NumericProperty): This is the current number of 
        entities in the system. Do not modify directly, used to generate 
        entity_ids.

        **gamescreenmanager** (ObjectProperty): Reference to the 
        GameScreenManager your game will use for UI screens.

        **entities** (list): entities is a list of all entity objects, 
        entity_id corresponds to position in this list.

        **states** (dict): states is a dict of lists of system_ids with keys 
        'systems_added','systems_removed', 'systems_paused', 'systems_unpaused'

        **entities_to_remove** (list): list of entity_ids that will be cleaned 
        up in the next cleanup update tick

        **system_manager** (SystemManager): Registers all the GameSystem added
        to the GameWorld and contains information for allocation and use of 
        those GameSystem.

        **master_buffer** (object): Typically a Buffer, the base memory from
        which all other static allocating memory objects will allocate from.

        **system_count** (NumericProperty): The number of systems that will 
        have memory allocated for them in the entities array.

        **update_time** (NumericProperty): The update interval.

        **size_of_entity_block** (NumericProperty): The size in kibibytes of 
        the Entity MemoryBlocks.

        **size_of_gameworld** (NumericProperty): The size in kibibytes of the 
        entire GameWorld's static allocation.

        **zones** (DictProperty): The zone name and count pairings for static
        allocation. Dict is zones[zone_name] = entity_count (int).

        **model_manager** (ModelManager): Handles the loading of VertexModels.
        You should only load model data using this ModelManager. Do not
        instantiate your own.
        
    '''
    state = StringProperty('initial')
    gamescreenmanager = ObjectProperty(None)
    zones = DictProperty({})
    size_of_gameworld = NumericProperty(1024)
    size_of_entity_block = NumericProperty(16)
    update_time = NumericProperty(1./60.)
    system_count = NumericProperty(DEFAULT_SYSTEM_COUNT)
    model_format_allocations = DictProperty({})
 
    
    def __init__(self, **kwargs):
        self.canvas = RenderContext(use_parent_projection=True,
            use_parent_modelview=True)
        self.systems_to_add = []
        super(GameWorld, self).__init__(**kwargs)
        self.states = {}
        self.state_callbacks = {}
        self.entity_manager = None
        self.entities = None
        self._last_state = 'initial'
        self._system_count = DEFAULT_SYSTEM_COUNT
        self.entities_to_remove = []
        self.system_manager = SystemManager()
        self.master_buffer = None
        self.model_manager = ModelManager()

    def ensure_startup(self, list_of_systems):
        '''Run during **init_gameworld** to determine whether or not it is safe
        to begin allocation. Safe in this situation means that every system_id 
        that has been listed in list_of_systems has been added to the GameWorld.

        Args:
            list_of_systems (list): List of the system_id (string) names of 
            the GameSystems we expect to have initialized.

        Return:
            bool : True if systems all added, otherwise False.
        '''
        systems_to_add = [x.system_id for x in self.systems_to_add]
        for each in list_of_systems:
            if each not in systems_to_add:
                Logger.error(
                    'GameSystem: System_id: {system_id} not attached retrying ' 
                    'in 1 sec. If you see this error once or twice, we are ' 
                    'probably just waiting on the KV file to load. If you see '
                    'it a whole bunch something is probably wrong. Make sure '
                    'all systems are setup properly.'.format(system_id=each))
                return False
        return True

    def allocate(self):
        '''Typically called interally as part of init_gameworld, this function
        allocates the **master_buffer** for the gameworld, registers the 
        zones, allocates the EntityManager, and calls allocate on all 
        GameSystem with do_allocation == True.
        '''
        cdef Buffer master_buffer = Buffer(self.size_of_gameworld*1024, 
            1, 1)
        self.master_buffer = master_buffer
        cdef SystemManager system_manager = self.system_manager
        master_buffer.allocate_memory()
        cdef unsigned int real_size = master_buffer.real_size
        cdef FormatConfig format_config
        for each in format_registrar._vertex_formats:
            format_config = format_registrar._vertex_formats[each]
            Logger.info('KivEnt: Vertex Format: {name} registered. Size per '
                'vertex is: {size}. Format is {format}.'.format(
                name=format_config._name,
                size=str(format_config._size),
                format=format_config._format))
        zones = self.zones
        if 'general' not in zones:
            zones['general'] = DEFAULT_COUNT
        cdef dict copy_from_obs_dict = {}
        for key in zones:
            copy_from_obs_dict[key] = zones[key]
            system_manager.add_zone(key, zones[key])
        system_count = self.system_count
        if system_count is None:
            system_count = self._system_count
        system_manager.set_system_count(system_count)
        for each in self.systems_to_add:
            system_manager.add_system(each.system_id, each)
        self.systems_to_add = None
        self.entity_manager = entity_manager = EntityManager(master_buffer, 
            self.size_of_entity_block, copy_from_obs_dict, system_count)
        self.entities = entity_manager.memory_index
        system_names = system_manager.system_index
        systems = system_manager.systems
        cdef MemoryZone memory_zone
        cdef IndexedMemoryZone memory_index
        total_count = entity_manager.get_size()
        for name in system_names:
            system_id = system_names[name]
            system = systems[system_id]
            if system.do_allocation:
                system_manager.configure_system_allocation(name)
                config_dict = system_manager.get_system_config_dict(name)
                size_estimate = system.get_size_estimate(config_dict)
                if total_count//1024 + size_estimate > real_size//1024:
                    raise GameWorldOutOfSpaceError(('System Name: {name} will ' 
                        'need {size_estimate} KiB, we have only: ' 
                        '{left} KiB').format(name=name, 
                        size_estimate=str(size_estimate), 
                        left=str((real_size-total_count)//1024),
                        ))

                system.allocate(master_buffer, config_dict)
                system_size = system.get_system_size()
                Logger.info(('KivEnt: {system_name} allocated {system_size} '  
                    'KiB').format(system_name=str(name), 
                    system_size=str(system_size//1024)))
                total_count += system_size
        total_count += self.model_manager.allocate(master_buffer, 
            dict(self.model_format_allocations))

        Logger.info(('KivEnt: We will need {total_count} KiB for game, we ' +
            'have {real_size} KiB').format(total_count=str(total_count//1024), 
                real_size=str(real_size//1024)))

    def init_gameworld(self, list_of_systems, callback=None):
        '''This function should be called once by your application during
        initialization. It will handle ensuring all GameSystem added in 
        kv lang have been initialized and call **allocate** afterwards.
        Once allocation has finished, the **update** for GameWorld will be
        Clock.schedule_interval for **update_time**. If kwarg callback is not
        None your callback will be called with no extra arguments.

        Args:
            list_of_systems (list): list of system_id (string) names for the 
            GameSystems we want to check have been initialized and added to
            GameWorld.

        Kwargs:
            callback (object): If not None will be invoked after allocate has
            returned and update scheduled. Defaults to None.
        '''
        if self.ensure_startup(list_of_systems):
            self.allocate()
            Clock.schedule_interval(self.update, self.update_time)
            if callback is not None:
                callback()
        else:
            Clock.schedule_once(
                lambda dt: self.init_gameworld(list_of_systems, 
                    callback=callback), 1.0)

    def add_state(self, state_name, screenmanager_screen=None, 
        systems_added=None, systems_removed=None, systems_paused=None, 
        systems_unpaused=None, on_change_callback=None):
        '''
        Args:
            state_name (str): Name for this state, should be unique.

        Kwargs:
            screenmanager_screen (str): Name of the screen for 
            GameScreenManager to make current when this state is transitioned
            into. Default None.

            systems_added (list): List of system_id that should be added
            to the GameWorld canvas when this state is transitioned into. 
            Default None.

            systems_removed (list): List of system_id that should be removed
            from the GameWorld canvas when this state is transitioned into.
            Default None.

            systems_paused (list): List of system_id that will be paused
            when this state is transitioned into. Default None.

            systems_unpaused (list): List of system_id that will be unpaused 
            when this state is transitioned into. Default None.

            on_change_callback (object): Callback function that will receive
            args of state_name, previous_state_name. The callback
            will run after the state change has occured. Callback will
            be called with arguments current_state, last_state. Default None.


        This function adds a new state for your GameWorld that will help you
        organize which systems are active in canvas, paused, or unpaused,
        and help you link that up to a Screen for the GameScreenManager
        so that you can sync your UI and game logic.
        '''
        if systems_added is None:
            systems_added = []
        if systems_removed is None:
            systems_removed = []
        if systems_paused is None:
            systems_paused = []
        if systems_unpaused is None:
            systems_unpaused = []
        self.states[state_name] = {'systems_added': systems_added, 
            'systems_removed': systems_removed, 
            'systems_paused': systems_paused, 
            'systems_unpaused': systems_unpaused}
        self.gamescreenmanager.states[state_name] = screenmanager_screen
        self.state_callbacks[state_name] = on_change_callback

    def on_state(self, instance, value):
        '''State change is handled here, systems will be added or removed
        in the order that they are listed. This allows control over the 
        arrangement of rendering layers. Later systems will be rendered on top
        of earlier.

        Args:
            instance (object): Should point to self.

            value(string): The name of the new state.

        If the state does not exist state will be reset to initial.
        '''
        try:
            state_dict = self.states[value]
        except KeyError: 
            self.state = 'initial'
            self._last_state = 'initial'
            print('State does not exist, resetting to initial')
            return

        gamescreenmanager = self.gamescreenmanager
        gamescreenmanager.state = value
        children = self.children
        cdef SystemManager system_manager = self.system_manager
        for system in state_dict['systems_added']:
            _system = system_manager[system]
            if _system in children:
                pass
            elif _system.gameview is not None:
                gameview_system = system_manager[_system.gameview]
                if _system in gameview_system.children:
                    pass
                else:
                    gameview_system.add_widget(_system)
            else:
                self.add_widget(_system)
        for system in state_dict['systems_removed']:
            _system = system_manager[system]
            if _system.gameview is not None:
                gameview = system_manager[_system.gameview]
                gameview.remove_widget(_system)
            elif _system in children:
                self.remove_widget(_system)
        for system in state_dict['systems_paused']:
            _system = system_manager[system]
            _system.paused = True
        for system in state_dict['systems_unpaused']:
            _system = system_manager[system]
            _system.paused = False
        state_callback = self.state_callbacks[value]
        if state_callback is not None:
            state_callback(value, self._last_state)
        self._last_state = value

    def get_entity(self, str zone):
        '''Used internally if there is not an entity currently available in
        deactivated_entities to create a new entity. Do not call directly.'''
        cdef EntityManager entity_manager = self.entity_manager
        entity_id = entity_manager.generate_entity(zone)
        return entity_id

    def init_entity(self, dict components_to_use, list component_order,
        zone='general'):
        '''
        Args:
            components_to_use (dict): A dict where keys are the system_id and
            values correspond to the component creation args for that 
            GameSystem.

            component_order (list): Should contain all system_id in
            components_to_use arg, ordered in the order you want component
            initialization to happen.

        This is the function used to create a new entity. It returns the 
        entity_id of the created entity. components_to_use is a dict of 
        system_id, args to generate_component function. component_order is
        the order in which the components should be initialized'''
        cdef unsigned int entity_id = self.get_entity(zone)
        cdef Entity entity = self.entities[entity_id]
        entity.load_order = component_order
        cdef SystemManager system_manager = self.system_manager
        entity.system_manager = system_manager
        cdef unsigned int system_id
        if debug:
            debug_str = 'KivEnt: Entity {entity_id} created with components: '
        for component in component_order:
            system = system_manager[component]
            system_id = system_manager.get_system_index(component)
            component_id = system.create_component(
                entity_id, zone, components_to_use[component])
            if debug:
                debug_str += component + ': ' + str(component_id) + ', '

        if debug:
            Logger.debug((debug_str).format(entity_id=str(entity_id)))
        return entity_id

    def timed_remove_entity(self, unsigned int entity_id, dt):
        '''
        Args:
            entity_id (unsigned int): The entity_id of the Entity to be removed 
            from the GameWorld.

            dt (float): Time argument passed by Kivy's Clock.schedule.

        This function can be used to schedule the destruction of an entity
        for a time in the future using partial and kivy's Clock.schedule_once
        
        Like:
            Clock.schedule_once(partial(
                gameworld.timed_remove_entity, entity_id))
        '''
        self.entities_to_remove.append(entity_id)

    def remove_entity(self, unsigned int entity_id):
        '''
        Args:
            entity_id (int): The entity_id of the Entity to be removed from
            the GameWorld

        This function immediately removes an entity from the gameworld. The 
        entity will have components removed in the reverse order from
        its load_order. 
        '''

        cdef Entity entity = self.entities[entity_id]
        cdef EntityManager entity_manager = self.entity_manager
        cdef SystemManager system_manager = self.system_manager
        entity._load_order.reverse()
        load_order = entity._load_order
        for system_name in load_order:
            system_manager[system_name].remove_component(
                entity.get_component_index(system_name))
            if debug:
                Logger.debug(('Remove component {comp_id} from entity'
                ' {entity_id}').format(
                    comp_id=system_name, 
                    entity_id=str(entity_id)))
        entity.load_order = []
        entity_manager.remove_entity(entity_id)

    def update(self, dt):
        '''
        Args:
            dt (float): Time argument, usually passed in automatically 
            by Kivy's Clock.

        Call the update function in order to advance time in your gameworld.
        Any GameSystem that is updateable and not paused will be updated. 
        Typically you will call this function using either Clock.schedule_once
        or Clock.schedule_interval
        '''
        cdef SystemManager system_manager = self.system_manager
        cdef list systems = system_manager.systems
        cdef GameSystem system
        for system_index in system_manager._update_order:
            system = systems[system_index]
            if system.updateable and not system.paused:
                system._update(dt)
        self.remove_entities()

    def remove_entities(self):
        '''Used internally to remove entities as part of the update tick'''
        original_ent_remove = self.entities_to_remove
        if len(original_ent_remove) == 0:
            return
        entities_to_remove = [entity_id for entity_id in original_ent_remove]
        remove_entity = self.remove_entity
        er = original_ent_remove.remove
        for entity_id in entities_to_remove:
            remove_entity(entity_id)
            er(entity_id)

    def clear_entities(self):
        '''Used to clear every entity in the GameWorld.'''
        entities = self.entities
        er = self.remove_entity
        entities_to_remove = [entity.entity_id for entity in memrange(self.entities)]
        for entity_id in entities_to_remove:
            er(entity_id)

    def delete_system(self, system_id):
        '''
        Args:
            system_id (str): The system_id of the GameSystem to be deleted
            from GameWorld.

        Used to delete a GameSystem from the GameWorld'''
        cdef SystemManager system_manager = self.system_manager
        system = system_manager[system_id]
        system.on_delete_system()
        system_manager.remove_system(system_id)
        self.remove_widget(system)

    def add_system(self, widget):
        '''Used internally by add_widget. Will register a previously unseen
        GameSystem with the system_manager, and call the GameSystem's 
        on_add_system function.

        Args:
            widget (GameSystem): the GameSystem to add to the GameWorld's
            system_manager.
        '''
        cdef SystemManager system_manager = self.system_manager
        system_index = system_manager.system_index
        if widget.system_id in system_index:
            return
        if system_manager.initialized:
            system_manager.add_system(widget.system_id, widget)
        else:
            self.systems_to_add.append(widget)
        widget.on_add_system()

    def add_widget(self, widget, index=0, canvas=None):
        '''Overrides the default add_widget from Kivy to ensure that
        we handle GameSystem related logic and can accept both Widget and
        CWidget base classes. If a GameSystem is added **add_system** will be
        called with that widget as the argument.

        Args:
            widget (Widget or CWidget): The widget to be added.

        Kwargs:
            index (int): The index to add this widget at in the children list.

            canvas (str): None, 'before', or 'after'; which canvas to add this
            widget to. None means base canvas and is default.
        '''
        cdef SystemManager system_manager = self.system_manager
        systems = system_manager.system_index
        if isinstance(widget, GameSystem):
            if widget.system_id not in systems and (
                widget not in self.systems_to_add):
                Clock.schedule_once(lambda dt: self.add_system(widget))
        if not (isinstance(widget, Widget) or isinstance(widget, CWidget)):
            raise WidgetException(
                'add_widget() can be used only with instances'
                ' of the Widget class.')

        widget = widget.__self__
        if widget is self:
            raise WidgetException(
                'Widget instances cannot be added to themselves.')
        parent = widget.parent
        # Check if the widget is already a child of another widget.
        if parent:
            raise WidgetException('Cannot add %r, it already has a parent %r'
                                  % (widget, parent))
        widget.parent = parent = self
        # Child will be disabled if added to a disabled parent.
        if parent.disabled:
            widget.disabled = True

        canvas = self.canvas.before if canvas == 'before' else \
            self.canvas.after if canvas == 'after' else self.canvas

        if index == 0 or len(self.children) == 0:
            self.children.insert(0, widget)
            canvas.add(widget.canvas)
        else:
            canvas = self.canvas
            children = self.children
            if index >= len(children):
                index = len(children)
                next_index = 0
            else:
                next_child = children[index]
                next_index = canvas.indexof(next_child.canvas)
                if next_index == -1:
                    next_index = canvas.length()
                else:
                    next_index += 1

            children.insert(index, widget)
            # We never want to insert widget _before_ canvas.before.
            if next_index == 0 and canvas.has_before:
                next_index = 1
            canvas.insert(next_index, widget.canvas)
        
    def remove_widget(self, widget):
        '''Same as Widget.remove_widget except that if the removed widget is a
        GameSystem, on_remove_system of that GameSystem will be ran.

        Args:
            widget (Widget or CWidget): the child to remove.
        '''
        if isinstance(widget, GameSystem):
            widget.on_remove_system()
        super(GameWorld, self).remove_widget(widget)
