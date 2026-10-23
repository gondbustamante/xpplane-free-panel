import SwiftUI
import XPlaneKit

/// Live view of every subscribed dataref. Array elements that changed in the last seconds light
/// up, so you can click a switch in the virtual cockpit and see which index moved. Also lets you
/// add datarefs to watch and fire commands by name, which is the whole mapping workflow without
/// leaving the iPad.
struct DiagnosticsView: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newDataref = ""
    @State private var commandName = ""

    private var names: [String] {
        // The MCDU screen is 150 text datarefs; the MCDU view itself is the way to inspect them.
        model.subscribedDatarefNames.filter { !$0.hasPrefix("AirbusFBW/MCDU1") && !$0.hasPrefix("AirbusFBW/MCDU2") }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                List {
                    Section("Añadir dataref a vigilar") {
                        HStack {
                            TextField("AirbusFBW/ElecOHPArray", text: $newDataref)
                                .font(.footnote.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addDataref)
                            Button("Añadir", action: addDataref)
                                .disabled(newDataref.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    Section("Lanzar comando") {
                        HStack {
                            TextField("toliss_airbus/lightcommands/NSSignUp", text: $commandName)
                                .font(.footnote.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(fireCommand)
                            Button("Enviar", action: fireCommand)
                                .disabled(commandName.trimmingCharacters(in: .whitespaces).isEmpty || model.status != .connected)
                        }
                        if let result = model.lastCommandResult {
                            Text(result).font(.footnote.monospaced()).foregroundStyle(.secondary)
                        }
                    }

                    Section("Datarefs suscritos (los elementos que cambian se iluminan 3 s)") {
                        if names.isEmpty {
                            Text("Nada suscrito. Conecta primero.").foregroundStyle(.secondary)
                        }
                        ForEach(names, id: \.self) { name in
                            datarefRow(name, now: context.date)
                        }
                    }
                }
            }
            .navigationTitle("Diagnóstico")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func datarefRow(_ name: String, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.footnote.monospaced().bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if model.unresolved.contains(name) {
                    Text("no existe").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                if model.isExtra(name) {
                    Button(role: .destructive) {
                        model.unwatch(dataref: name)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if let value = model.rawValues[name] {
                if let array = value.arrayValue {
                    indexGrid(name: name, array: array, now: now)
                } else {
                    Text(describe(value))
                        .font(.footnote.monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(model.recentlyChanged(name, now: now) ? Color.yellow.opacity(0.5) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } else {
                Text("sin valor todavía").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func indexGrid(name: String, array: [XPValue], now: Date) -> some View {
        let columns = [GridItem(.adaptive(minimum: 64), spacing: 4)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(Array(array.enumerated()), id: \.offset) { index, element in
                let changed = model.recentlyChanged("\(name)[\(index)]", now: now)
                HStack(spacing: 2) {
                    Text("[\(index)]").foregroundStyle(.secondary)
                    Text(describe(element)).bold()
                }
                .font(.caption.monospaced())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(changed ? Color.yellow.opacity(0.6) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func describe(_ value: XPValue) -> String {
        switch value {
        case .number(let number):
            if number.rounded() == number { return String(Int(number)) }
            return String(format: "%.3f", number)
        case .bool(let bool): return bool ? "1" : "0"
        case .string(let string): return "\"\(string)\""
        case .array(let array): return "[\(array.count)]"
        case .null: return "null"
        }
    }

    private func addDataref() {
        model.watch(dataref: newDataref)
        newDataref = ""
    }

    private func fireCommand() {
        model.fire(command: commandName)
    }
}
