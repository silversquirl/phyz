# Phyz

Phyz is a work-in-progress physics engine for 2D games, written in Zig.
Goals are simplicity, speed and ease of use, in that order.

## Progress

- [x] GJK algorithm
- [ ] Continuous collision detection
	- [x] Dynamic-Static
	- [ ] Dynamic-Dynamic
- [x] Fully customizable collision resolution
- [x] Broad phase
- [x] Queries
	- [x] Nearest object
	- [x] Raycast
	- [x] Objects in shape
- [ ] Handle intersecting colliders
- [ ] Collision masking
- [ ] Temporary collider disable flag
- [ ] Collider deletion
- [ ] More interesting actuators
	- [ ] Forcefields/magnetism
	- [ ] Constraints
- [ ] General purpose resolver
	- [ ] Friction
	- [ ] Bounce

## Non-goals

To keep the engine simple and fast, a number of things are purposefully not supported:

- Rotation and angular velocity
- Soft bodies
- Non-convex colliders (can be approximated using multiple convex colliders)
- Multiple colliders per object (can be approximated using constraints)

If you need support for these things, I recommend using a more complex physics engine
such as [Chipmunk2D] or [Box2D].

[Chipmunk2D]: https://chipmunk-physics.net/
[Box2D]: https://box2d.org/
