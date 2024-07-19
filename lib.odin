package tiny_ecs

/*
TODO:
- [ ] ECStorage struct
- [ ] usar `generational arenas`
- [ ] component register usando union?
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

Storage :: struct {
  component_storage      : map[typeid]runtime.Raw_Dynamic_Array,
  reusable_component_ids : map[typeid][dynamic]ComponentID,
  entity_storage         : [dynamic]Entity,
  reusable_entity_ids    : [dynamic]EntityID,

  // NOTE: map between compile-time known typeid to runtime typeid
  type_ids               : map[typeid]typeid,
}




// TODO: defer destroy
storage_register_component :: proc(using s: ^Storage, $T: typeid) {
  arr, err_arr := make_dynamic_array([dynamic]T)
  if err_arr != nil do assert(false)

  // TODO: criar uma struct para encapsular tudo?
  component_storage[T] = transmute(runtime.Raw_Dynamic_Array)arr
  reusable_component_ids[T] = make_dynamic_array([dynamic]ComponentID)
  type_ids[T] = typeid_of(type_of(arr))
}

storage_register_entity :: proc(using s: ^Storage) -> EntityID {

  entity_id, ok_entity_id := pop_safe(&reusable_entity_ids)
  if ok_entity_id && (int(entity_id) > 0 && int(entity_id) < len(entity_storage)) {
    entity_storage[entity_id].flags += { .ACTIVE }
    return entity_id
  }

  append_elem(&entity_storage, Entity{ flags={.ACTIVE}, components = make_map(map[typeid]ComponentID)})
  return EntityID(len(entity_storage)-1)
}

storage_entity_remove_component :: proc(using s: ^Storage, entity_id: EntityID, com: typeid){
  entity := entity_storage[entity_id]
  comp_id, ok_comp_id := entity.components[com]
  if !ok_comp_id do return

  delete_key(&entity.components, com)
  append_elem(&reusable_component_ids[com], comp_id)
}

storage_remove_entity :: proc(using s: ^Storage, entity_id: EntityID) {
  entity := &entity_storage[entity_id]

  if !(int(entity_id) >= 0 && int(entity_id) < len(entity_storage)) do return

  for comp, idx in entity.components {
    storage_entity_remove_component(s, entity_id, comp)
  }

  clear_map(&entity.components)
  entity.flags -= {.ACTIVE}
  append(&reusable_entity_ids, entity_id)
}

// TODO: query fn
query_components :: proc() {
  assert(false, "TODO")
}

entity_is_active :: proc {
  entity_non_ptr_is_active,
  entity_ptr_is_active,
}

entity_non_ptr_is_active :: proc(entity: Entity) -> bool {
  return (.ACTIVE in entity.flags)
}

entity_ptr_is_active :: proc(entity: ^Entity) -> bool {
  if entity == nil do return false
  return entity_non_ptr_is_active(entity^)
}

storage_entity_ptr :: proc(using s: ^Storage, id: EntityID) -> (entity: ^Entity, ok: bool) {
  if int(id) <= 0 && int(id) > len(entity_storage) {
    return nil, false
  }

  return &entity_storage[id],true
}

storage_entity_add_component :: proc(using s: ^Storage, entity_id: EntityID, com: $T) {
  comp_id := storage_create_component(s, com)
  entity_storage[entity_id].components[T] = comp_id
}

storage_entity_get_component_ptr :: proc(using s: ^Storage, entity_id: EntityID, $T: typeid) -> (component: ^T, ok: bool) {
  if !(int(entity_id) < len(entity_storage) && int(entity_id) >= 0) do return nil, false
  entity := entity_storage[entity_id]
  component_id := entity.components[T] or_return
  component_list := component_query(T)

  return &component_list[component_id], true
}

storage_entity_get_component :: proc(using s: ^Storage, entity_id: EntityID, $T: typeid) -> (component: T, ok: bool) {
  res := entity_get_component_ptr(entity_id, T) or_return
  return res^, true
}

storage_create_component :: proc(using s: ^Storage, item: $T) -> ComponentID {
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
  panic(fmt.tprintf("Component not registered: %v", reflect.typeid_elem(T)))
}

storage_query_component :: proc(using s: ^Storage, $T: typeid) -> []T {
  if T not_in component_storage {
    panic_not_t(T)
  }
  storage := transmute([dynamic]T)component_storage[T]
  return storage[:]
}

