//
//  DeckView.swift
//  
//
//  Created by nori on 2021/06/11.
//

import SwiftUI

public struct AllowedDirections: OptionSet {

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let left: AllowedDirections = AllowedDirections(rawValue: 1 << Direction.left.rawValue)
    public static let top: AllowedDirections = AllowedDirections(rawValue: 1 << Direction.top.rawValue)
    public static let right: AllowedDirections  = AllowedDirections(rawValue: 1 << Direction.right.rawValue)
    public static let bottom: AllowedDirections  = AllowedDirections(rawValue: 1 << Direction.bottom.rawValue)

    public static let vertical: AllowedDirections  = [.top, .bottom]
    public static let horizontal: AllowedDirections  = [.left, .right]
    public static let all: AllowedDirections  = [.vertical, .horizontal]
}

public struct Option {

    public var allowedDirections: AllowedDirections

    public var numberOfVisibleCards: Int

    public var maximumRotationOfCard: Double

    public var judgmentThreshold: CGFloat

    public init(
        allowedDirections: AllowedDirections = [.all],
        numberOfVisibleCards: Int = 5,
        maximumRotationOfCard: Double = 15,
        judgmentThreshold: CGFloat = 190
    ) {
        self.allowedDirections = allowedDirections
        self.numberOfVisibleCards = numberOfVisibleCards
        self.maximumRotationOfCard = maximumRotationOfCard
        self.judgmentThreshold = max(judgmentThreshold, 1)
    }

    public static func allowed(directions: AllowedDirections) -> Self {
        return Option(allowedDirections: directions)
    }
}

public struct CardState {

    public var offset: CGSize

    public var angle: Angle

    public init(
        offset: CGSize = .zero,
        angle: Angle = .zero
    ) {
        self.offset = offset
        self.angle = angle
    }
}

public struct DeckStack<Element: Identifiable, Content: View>: View {

    private var option: Option

    private var deck: Deck<Element>

    private var content: (Element, Element.ID) -> Content

    public init(
        _ deck: Deck<Element>,
        option: Option = Option(),
        @ViewBuilder content: @escaping (Element, Element.ID) -> Content
    ) {
        self.deck = deck
        self.option = option
        self.content = content
    }

    private var visibleStackData: [Element] {
        let start = max(deck.index - 1, 0)
        guard deck.data.count > start else {
            return []
        }
        let end = min(start + option.numberOfVisibleCards, deck.data.count - 1)
        return Array(deck.data[start..<end].reversed())
    }

    public var body: some View {
        ZStack {
            ForEach(visibleStackData, id: \.id) { data in
                DeckStackWrapperView(id: data.id, option: option) {
                    content(data, deck.data[deck.index].id)
                }
                .zIndex(Double(visibleStackData.firstIndex(where: { $0.id == data.id }) ?? 0))
                .environmentObject(deck)
            }
        }
    }

    public func onGesture(_ gesture: DeckDragGesture) -> Self {
        self.deck.dragGesture = gesture
        return self
    }

    public func onJudged(perform: @escaping (Element.ID, Direction) -> Void) -> Self {
        self.deck.onJudged = perform
        return self
    }

    struct DeckStackWrapperView<Content: View>: View {

        @EnvironmentObject var deck: Deck<Element>

        private var id: Element.ID

        private var option: Option

        private var content: () -> Content

        init(
            id: Element.ID,
            option: Option,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.id = id
            self.option = option
            self.content = content
        }

        private func direction(from translation: CGSize) -> Direction {
            var direction: Direction = .none
            switch (translation.height, translation.width) {
                case (let vertical, let horizontal) where abs(vertical) > abs(horizontal) && vertical < 0: direction = .top
                case (let vertical, let horizontal) where abs(vertical) > abs(horizontal) && vertical > 0: direction = .bottom
                case (let vertical, let horizontal) where abs(vertical) < abs(horizontal) && horizontal > 0: direction = .right
                case (let vertical, let horizontal) where abs(vertical) < abs(horizontal) && horizontal < 0: direction = .left
                default: direction = .none
            }
            if option.allowedDirections.contains(AllowedDirections(rawValue: 1 << direction.rawValue)) {
                return direction
            }
            return .none
        }

        private func progress(from translation: CGSize) -> CGFloat {
            let translationAbs: CGFloat = max(abs(translation.width), abs(translation.height))
            return min(translationAbs / option.judgmentThreshold, 1.0)
        }

        private func estimateProgress(from predictedEndTranslation: CGSize) -> CGFloat {
            let predictedEndTranslationAbs: CGFloat = max(abs(predictedEndTranslation.width), abs(predictedEndTranslation.height))
            return min(predictedEndTranslationAbs / option.judgmentThreshold, 1.0)
        }

        private func getGestureState(from value: DragGesture.Value) -> DeckDragGestureState {
            let direction: Direction = self.direction(from: value.translation)
            let progress: CGFloat = self.progress(from: value.translation)
            let estimateProgress: CGFloat = self.estimateProgress(from: value.predictedEndTranslation)
            let offset = value.translation
            let angle = Angle(degrees: Double(min(value.translation.width / option.judgmentThreshold, 1.0)) * option.maximumRotationOfCard)
            return DeckDragGestureState(
                direction: direction,
                progress: progress,
                estimateProgress: estimateProgress,
                translation: value.translation,
                offset: offset,
                angle: angle
            )
        }

        var offset: CGSize { deck.properties[id]?.offset ?? .zero }

        var angle: Angle { deck.properties[id]?.angle ?? .zero }

        var body: some View {
            Group {
                content()
                    .offset(offset)
                    .rotationEffect(angle)
            }
            .gesture(
                DragGesture()
                    .onChanged({ value in
                        let gestureState: DeckDragGestureState = self.getGestureState(from: value)
                        self.deck.properties[id]?.offset = gestureState.translation
                        self.deck.properties[id]?.angle = gestureState.angle
                        self.deck.dragGesture?.onChangeHandler?(gestureState)
                    })
                    .onEnded({ value in
                        let gestureState: DeckDragGestureState = self.getGestureState(from: value)
                        if gestureState.direction == .none {
                            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.67, blendDuration: 0.8)) {
                                self.deck.properties[id]?.offset = .zero
                                self.deck.properties[id]?.angle = .zero
                            }
                            self.deck.dragGesture?.onEndHandler?(gestureState)
                            return
                        }
                        if gestureState.isJudged {
                            deck.swipe(to: gestureState.direction, id: id)
                        } else {
                            deck.cancel(id: id)
                        }
                        self.deck.dragGesture?.onEndHandler?(gestureState)
                    })
            )
        }
    }

}
