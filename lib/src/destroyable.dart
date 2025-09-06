/// An object that maintains destroyable resource.
/// They need to be destroyed when time is right.
abstract class Destroyable {
  void reset();
  void destroy();
}
