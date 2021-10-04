let pow2 x = 1 lsl x

module Make (Arg : Varray_sig.ARRAY)
: sig
    include Varray_sig.TIER with type 'a Array.t = 'a Arg.t
                             and type 'a Array.elt = 'a Arg.elt

    val set_length : 'a t -> int -> unit
    val grow_head : lc:int -> 'a t -> unit
    val grow_tail : 'a t -> unit
    val unsafe_pop_front : lc:int -> 'a t -> unit
    val unsafe_pop_back : lc:int -> 'a t -> unit
end
= struct

  module Array = Arg
  type 'a elt = 'a Array.elt
  type 'a array = 'a Array.t

  type 'a t =
    { mutable head: int
    ; mutable length: int
    ; buffer: 'a Array.t
    }

  let depth = 1

  let length t = t.length

  let is_empty t = t.length = 0

  let capacity ~lc:_ t = Array.length t.buffer

  let root_capacity = capacity

  let is_full ~lc t = t.length = capacity ~lc t

  let set_length t len = t.length <- len

  let empty =
    Obj.magic
      { head = 0
      ; length = 0
      ; buffer = Array.empty
      }

  let create ~capacity =
    { head = 0
    ; length = 0
    ; buffer = Array.create capacity
    }

  let make ~lc n x =
    let capacity = pow2 lc in
    assert (capacity > 0) ;
    let buffer = Array.create capacity in
    for i = 0 to n - 1 do
      Array.set buffer i x
    done ;
    { head = 0
    ; length = n
    ; buffer
    }

  let init ~lc ~offset n f =
    let capacity = pow2 lc in
    assert (capacity > 0) ;
    let buffer = Array.create capacity in
    for i = 0 to n - 1 do
      let x = f (i + offset) in
      Array.set buffer i x
    done ;
    { head = 0
    ; length = n
    ; buffer
    }

  let index ~lc t i = (t.head + i) mod capacity ~lc t
  let index_last ~lc t = index ~lc t (t.length - 1)

  let get ~lc t i =
    assert (i >= 0 && i < t.length) ;
    t.buffer.(index ~lc t i)

  let set ~lc t i x =
    assert (i >= 0 && i < t.length) ;
    t.buffer.(index ~lc t i) <- x

  let shift_right ~lc t j =
    let tail = index ~lc t t.length in
    if j <= tail
    then Array.blit t.buffer j t.buffer (j + 1) (tail - j)
    else begin
      let cap = capacity ~lc t in
      let last = t.buffer.(cap - 1) in
      Array.blit t.buffer j t.buffer (j + 1) (cap - j - 1) ;
      Array.blit t.buffer 0 t.buffer 1 tail ;
      t.buffer.(0) <- last
    end

  let shift_left ~lc t j =
    let head = t.head in
    let cap = capacity ~lc t in
    if j >= head
    then begin
      let prev = (head - 1 + cap) mod cap in
      t.buffer.(prev) <- t.buffer.(head) ;
      Array.blit t.buffer (head + 1) t.buffer head (j - head)
    end
    else begin
      Array.blit t.buffer head t.buffer (head - 1) (cap - head) ;
      t.buffer.(cap - 1) <- t.buffer.(0) ;
      Array.blit t.buffer 1 t.buffer 0 j ;
    end

  let head_left ~lc t =
    let cap = capacity ~lc t in
    t.head <- (t.head - 1 + cap) mod cap

  let grow_tail t =
    t.length <- t.length + 1

  let grow_head ~lc t =
    assert (t.length < capacity ~lc t) ;
    head_left ~lc t ;
    grow_tail t

  let push_front ~lc t x =
    assert (t.length < capacity ~lc t) ;
    grow_head ~lc t ;
    t.buffer.(t.head) <- x

  let push_back ~lc t x =
    assert (t.length < capacity ~lc t) ;
    grow_tail t ;
    t.buffer.(index_last ~lc t) <- x

  let make_room ~lc t i =
    assert (t.length < capacity ~lc t) ;
    if 2 * i >= t.length
    then begin
      let j = index ~lc t i in
      shift_right ~lc t j ;
      grow_tail t
    end
    else begin
      let j = index ~lc t i in
      shift_left ~lc t j ;
      grow_head ~lc t
    end

  let insert_at ~lc t i x =
    assert (i >= 0 && i <= t.length) ;
    assert (t.length < capacity ~lc t) ;
    make_room ~lc t i ;
    set ~lc t i x


  let shrink_tail t tail =
    Array.erase_at t.buffer tail ;
    t.length <- t.length - 1

  let shrink_head ~lc t head =
    Array.erase_at t.buffer head ;
    t.head <- (head + 1) mod capacity ~lc t ;
    t.length <- t.length - 1


  let shrink_prev_head ~lc t =
    let cap = capacity ~lc t in
    if t.length + 1 < cap
    then let prev = (t.head - 1 + cap) mod cap in
         Array.erase_at t.buffer prev

  let shrink_next_tail ~lc t =
    let cap = capacity ~lc t in
    if t.length + 1 < cap
    then let next = (t.head + t.length) mod cap in
         Array.erase_at t.buffer next

  let unsafe_pop_front ~lc t =
    shrink_prev_head ~lc t ;
    let cap = capacity ~lc t in
    t.head <- (t.head + 1) mod cap ;
    t.length <- t.length - 1

  let unsafe_pop_back ~lc t =
    shrink_next_tail ~lc t ;
    t.length <- t.length - 1

  let delete_right ~lc t j =
    let tail = index_last ~lc t in
    if j = tail
    then ()
    else if j < tail
    then Array.blit t.buffer (j + 1) t.buffer j (tail - j)
    else begin
      let cap = capacity ~lc t in
      Array.blit t.buffer (j + 1) t.buffer j (cap - 1 - j) ;
      t.buffer.(cap - 1) <- t.buffer.(0) ;
      Array.blit t.buffer 1 t.buffer 0 tail
    end ;
    shrink_tail t tail

  let delete_left ~lc t j =
    let head = t.head in
    if j = head
    then ()
    else if head < j
    then Array.blit t.buffer head t.buffer (head + 1) (j - head)
    else begin
      let cap = capacity ~lc t in
      let last = t.buffer.(cap - 1) in
      Array.blit t.buffer head t.buffer (head + 1) (cap - 1 - head) ;
      Array.blit t.buffer 0 t.buffer 1 j ;
      t.buffer.(0) <- last ;
    end ;
    shrink_head ~lc t head

  let delete_at ~lc t i =
    let j = index ~lc t i in
    if 2 * i >= t.length
    then delete_right ~lc t j
    else delete_left ~lc t j

  let pop_at ~lc t i =
    let x = get ~lc t i in
    delete_at ~lc t i ;
    x

  let pop_front ~lc t =
    assert (t.length > 0) ;
    let x = t.buffer.(t.head) in
    shrink_head ~lc t t.head ;
    x

  let pop_back ~lc t =
    assert (t.length > 0) ;
    let tail = index_last ~lc t in
    let x = t.buffer.(tail) in
    shrink_tail t tail ;
    x

  let push_front_pop_back ~lc t x =
    let tail = index_last ~lc t in
    let last = t.buffer.(tail) in
    head_left ~lc t ;
    t.buffer.(t.head) <- x ;
    last

  let push_back_pop_front ~lc t x =
    let first = t.buffer.(t.head) in
    t.head <- index ~lc t 1 ;
    let last = index_last ~lc t in
    t.buffer.(last) <- x ;
    first

end
