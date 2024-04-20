package ecs_engine

/*
TODO:
- [ ] memory managment with temporary entities
- [ ] add union?
- [ ] entity internal use via pointer?
*/

import "core:fmt"
import "core:reflect"
import "base:runtime"
import "core:strings"


ComponentID :: distinct u32
EntityID    :: distinct u32
Entity      :: struct {
  flags: bit_set[enum u8 { ACTIVE }],
  components: map[typeid]ComponentID,
}

component_storage      : map[typeid]runtime.Raw_Dynamic_Array = {}
reusable_component_ids : map[typeid][dynamic]ComponentID = {}
type_ids               : map[typeid]typeid = {}

entity_storage : [dynamic]Entity = {}
reusable_entity_ids : [dynamic]EntityID = {}

// TODO: defer destroy
component_register :: proc($T: typeid) {
  arr, err_arr := make_dynamic_array([dynamic]T)
  if err_arr != nil do assert(false)

  // TODO: criar uma struct para encapsular tudo?
  component_storage[T] = transmute(runtime.Raw_Dynamic_Array)arr
  reusable_component_ids[T] = make_dynamic_array([dynamic]ComponentID)
  type_ids[T] = typeid_of(type_of(arr))
}

entity_register :: proc() -> EntityID {

  entity_id, ok_entity_id := pop_safe(&reusable_entity_ids)
  if ok_entity_id && (int(entity_id) > 0 && int(entity_id) < len(entity_storage)) {
    entity_storage[entity_id].flags += { .ACTIVE }
    return entity_id
  }

  append_elem(&entity_storage, Entity{ flags={.ACTIVE}, components = make_map(map[typeid]ComponentID)})
  return EntityID(len(entity_storage)-1)
}

entity_remove_component :: proc(entity_id: EntityID, com: $T/typeid){
  entity := entity_storage[entity_id]
  comp_id, ok_comp_id := entity.components[com]
  if !ok_comp_id do return

  delete_key(&entity.components, com)
  append_elem(&reusable_component_ids[com], comp_id)
}

entity_remove :: proc(entity_id: EntityID) {
  entity := &entity_storage[entity_id]

  if !(int(entity_id) >= 0 && int(entity_id) < len(entity_storage)) do return

  for comp, idx in entity.components {
    entity_remove_component(entity_id, comp)
  }

  clear_map(&entity.components)
  entity.flags -= {.ACTIVE}
  append(&reusable_entity_ids, entity_id)
}

// TODO: query fn
query_components :: proc() {
  assert(false, "TODO")
}

entity_is_active :: proc(entity: ^Entity) -> bool {
  if entity == nil do return false
  return (.ACTIVE in entity.flags)
}

entity_ref :: proc(id: EntityID) -> (entity: ^Entity, ok: bool) {
  if int(id) <= 0 && int(id) > len(entity_storage) {
    return nil, false
  }

  return &entity_storage[id],true
}

entity_add_component :: proc(entity_id: EntityID, com: $T) {
  comp_id := component_add(com)
  entity_storage[entity_id].components[T] = comp_id
}

entity_get_component_read_write :: proc(entity_id: EntityID, $T: typeid) -> (component: ^T, ok: bool) {
  if !(int(entity_id) < len(entity_storage) && int(entity_id) >= 0) do return nil, false
  entity := entity_storage[entity_id]
  component_id := entity.components[T] or_return
  component_list := component_query(T)

  return &component_list[component_id], true
}

entity_get_component_read_only :: proc(entity_id: EntityID, $T: typeid) -> (component: T, ok: bool) {
  if !(int(entity_id) < len(entity_storage) && int(entity_id) >= 0) do return {}, false
  entity := entity_storage[entity_id]
  component_id := entity.components[T] or_return
  component_list := component_query(T)

  return component_list[component_id], true
}

component_add :: proc(item: $T) -> ComponentID {
  if !(T in component_storage) {
    panic_not_t(T)
  }

  storage := transmute(^[dynamic]T)&component_storage[T]
  
  comp_id, ok_comp_id := pop_safe(&reusable_component_ids[T])

  if ok_comp_id {
    storage[comp_id] = item
    return comp_id
  }

  append_elem(storage, item)

  return ComponentID(len(storage)-1)
}

panic_not_t :: proc($T: typeid){
  builder := strings.builder_make(allocator=context.temp_allocator)
  fmt.sbprintf(&builder, "Component not registered: %v", reflect.typeid_elem(T))
  panic(strings.to_string(builder))
}

component_query :: proc($T: typeid) -> []T {
  if T not_in component_storage {
    panic_not_t(T)
  }
  storage := transmute([dynamic]T)component_storage[T]
  return storage[:]
}

