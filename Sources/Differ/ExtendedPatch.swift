enum BoxedDiffAndPatchElement<T: Codable> {
    case move(
        diffElement: ExtendedDiff.Element,
        deletion: SortedPatchElement<T>,
        insertion: SortedPatchElement<T>
    )
    case single(
        diffElement: ExtendedDiff.Element,
        patchElement: SortedPatchElement<T>
    )

    var diffElement: ExtendedDiff.Element {
        switch self {
        case let .move(de, _, _):
            return de
        case let .single(de, _):
            return de
        }
    }
}

/// Single step in a patch sequence.
public enum ExtendedPatch<Element: Codable>: Codable {
    /// A single patch step containing the origin and target of a move
    case insertion(index: Int, element: Element)
    /// A single patch step containing a deletion index
    case deletion(index: Int)
    /// A single patch step containing the origin and target of a move
    case move(from: Int, to: Int)
}

/// Generates a patch sequence. It is a list of steps to be applied to obtain the `to` collection from the `from` one. The sorting function lets you sort the output e.g. you might want the output patch to have insertions first.
///
/// - Complexity: O((N+M)*D)
///
/// - Parameters:
///   - from: The source collection
///   - to: The target collection
///   - sort: A sorting function
/// - Returns: Arbitrarly sorted sequence of steps to obtain `to` collection from the `from` one.
public func extendedPatch<T: Collection>(
    from: T,
    to: T,
    sort: ExtendedDiff.OrderedBefore? = nil
) -> [ExtendedPatch<T.Element>] where T.Element: Equatable {
    return from.extendedDiff(to).patch(from: from, to: to, sort: sort)
}

extension ExtendedDiff {
    public typealias OrderedBefore = (_ fst: ExtendedDiff.Element, _ snd: ExtendedDiff.Element) -> Bool

    /// Generates a patch sequence based on the callee. It is a list of steps to be applied to obtain the `to` collection from the `from` one. The sorting function lets you sort the output e.g. you might want the output patch to have insertions first.
    ///
    /// - Complexity: O(D^2)
    ///
    /// - Parameters:
    ///   - from: The source collection (usually the source collecetion of the callee)
    ///   - to: The target collection (usually the target collecetion of the callee)
    ///   - sort: A sorting function
    /// - Returns: Arbitrarly sorted sequence of steps to obtain `to` collection from the `from` one.
    public func patch<T: Collection>(
        from: T,
        to: T,
        sort: OrderedBefore? = nil
    ) -> [ExtendedPatch<T.Element>] {

        let result: [SortedPatchElement<T.Element>]
        if let sort = sort {
            result = shiftedPatchElements(from: generateSortedPatchElements(from: from, to: to, sort: sort))
        } else {
            result = shiftedPatchElements(from: generateSortedPatchElements(from: from, to: to))
        }

        return result.indices.compactMap { i -> ExtendedPatch<T.Element>? in
            let patchElement = result[i]
            if moveIndices.contains(patchElement.sourceIndex) {
                let to = result[i + 1].value
                switch patchElement.value {
                case let .deletion(index):
                    if case let .insertion(toIndex, _) = to {
                        return .move(from: index, to: toIndex)
                    } else {
                        fatalError()
                    }
                case let .insertion(index, _):
                    if case let .deletion(fromIndex) = to {
                        return .move(from: fromIndex, to: index)
                    } else {
                        fatalError()
                    }
                }
            } else if !(i > 0 && moveIndices.contains(result[i - 1].sourceIndex)) {
                switch patchElement.value {
                case let .deletion(index):
                    return .deletion(index: index)
                case let .insertion(index, element):
                    return .insertion(index: index, element: element)
                }
            }
            return nil
        }
    }

    func generateSortedPatchElements<T: Collection>(
        from: T,
        to: T,
        sort: @escaping OrderedBefore
    ) -> [SortedPatchElement<T.Element>] {
        let unboxed = boxDiffAndPatchElements(
            from: from,
            to: to
        ).sorted { from, to -> Bool in
            return sort(from.diffElement, to.diffElement)
        }.flatMap(unbox)

        return unboxed.indices.map { index -> SortedPatchElement<T.Element> in
            let old = unboxed[index]
            return SortedPatchElement(
                value: old.value,
                sourceIndex: old.sourceIndex,
                sortedIndex: index)
        }.sorted { (fst, snd) -> Bool in
            fst.sourceIndex < snd.sourceIndex
        }
    }

    func generateSortedPatchElements<T: Collection>(from: T, to: T) -> [SortedPatchElement<T.Element>] {
        let patch = source.patch(to: to)
        return patch.indices.map {
            SortedPatchElement(
                value: patch[$0],
                sourceIndex: $0,
                sortedIndex: reorderedIndex[$0]
            )
        }
    }

    func boxDiffAndPatchElements<T: Collection>(
        from: T,
        to: T
    ) -> [BoxedDiffAndPatchElement<T.Element>] {
        let sourcePatch = generateSortedPatchElements(from: from, to: to)
        var indexDiff = 0
        return elements.indices.map { i in
            let diffElement = elements[i]
            switch diffElement {
            case .move:
                indexDiff += 1
                return .move(
                    diffElement: diffElement,
                    deletion: sourcePatch[sourceIndex[i + indexDiff - 1]],
                    insertion: sourcePatch[sourceIndex[i + indexDiff]]
                )
            default:
                return .single(
                    diffElement: diffElement,
                    patchElement: sourcePatch[sourceIndex[i + indexDiff]]
                )
            }
        }
    }
}

func unbox<T: Codable>(_ element: BoxedDiffAndPatchElement<T>) -> [SortedPatchElement<T>] {
    switch element {
    case let .move(_, deletion, insertion):
        return [deletion, insertion]
    case let .single(_, patchElement):
        return [patchElement]
    }
}

extension ExtendedPatch: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .deletion(at):
            return "D(\(at))"
        case let .insertion(at, element):
            return "I(\(at),\(element))"
        case let .move(from, to):
            return "M(\(from),\(to))"
        }
    }
}
