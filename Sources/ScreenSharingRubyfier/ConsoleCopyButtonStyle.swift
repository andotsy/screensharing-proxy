import SwiftUI

struct ConsoleCopyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(configuration.isPressed ? 0.2 : 0),
                        in: .rect(cornerRadius: 5))
            .contentShape(.rect)
    }
}
