import SwiftUI

struct AvatarView: View {
    let photoData: Data?
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                let colors = Theme.avatarColors(for: initials)
                ZStack {
                    Circle().fill(colors.fill)
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.text)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
