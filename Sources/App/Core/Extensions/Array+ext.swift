import NIO


extension Array {

    /// Map `Result<T, E>` elements with the given `transform` to `EventLoopFuture<U>`by transforming the sucess case and passing through the error `E` in case of failures.
    /// - Parameters:
    ///   - eventLoop: event loop
    ///   - transform: transformation
    /// - Returns: array of futures
    func map<T, U, E>(on eventLoop: EventLoop,
                      transform: (T) -> EventLoopFuture<U>) -> [EventLoopFuture<U>] where Element == Result<T, E> {
        map { result in
            switch result {
                case .success(let v): return transform(v)
                case .failure(let e): return eventLoop.future(error: e)
            }
        }
    }

    /// Returns a new `EventLoopFuture` that succeeds when all `Result<T, Error>` elements transformed into `EventLoopFuture<U>` elements have completed.
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` on which the new `EventLoopFuture` callbacks will fire.
    ///   - transform: The transformation to be applied to the `Array`'s elements
    /// - Returns: A new `Array` with the results of the transformation, wrapped in `Result`s.
    func whenAllComplete<T, U>(on eventLoop: EventLoop,
                               transform: (T) -> EventLoopFuture<U>) -> EventLoopFuture<[Result<U, Error>]> where Element == Result<T, Error> {
        EventLoopFuture.whenAllComplete(
            map(on: eventLoop, transform: transform),
            on: eventLoop
        )
    }

}
