"""Baut die Unterverteilung der Halle C (gelbe Traegerplatte mit 2 x 7 Steckdosen) fuer DataCenter Tycoon.

Aufruf erfolgt aus build_utilities.build_all(). Die Masse stammen aus
scripts/world/garage_builder.gd, Funktion _build_hall_c_subpanel(), und sind in Godot-Koordinaten notiert.
Jede Steckdose und jede Abdeckung ist ein eigenes Mesh mit der Property dct_socket_index,
damit das Spiel die Abdeckungen einzeln ein- und ausblenden kann.
"""

HALL_C_GAME_POS = (14.6, 1.55, -4.38)
HALL_C_AT = (3.0, 3.0, 1.55)  # Vorschauposition in Blender. Der Export setzt den Ursprung auf 0.
HALL_C_SOCKET_COLS = 7
HALL_C_SOCKET_ROWS = 2


def socket_pos(row, col):
    """Mittelpunkt einer Steckdose in Godot-Koordinaten relativ zum Unterverteiler."""
    return (-0.255 + 0.085 * float(col), -0.20 - 0.13 * float(row), 0.126)


def build_hall_c_subpanel(coll, M, GPart, make_root, add_text):
    root = make_root(coll, "hall_c_subpanel", HALL_C_AT, HALL_C_GAME_POS)

    # Gehaeuse und gelbe Traegerplatte
    housing = GPart("hall_c_subpanel_Housing")
    housing.gbox((0.0, 0.0, 0.0), (0.72, 0.94, 0.20), M["hall_c_housing"])
    housing.gbox((0.0, -0.265, 0.11), (0.64, 0.25, 0.02), M["socket_yellow"])
    housing.build(coll, root)

    # Beschriftung auf der Vorderseite
    add_text(coll, root, "hall_c_subpanel_Txt_Label", "HALLE-C STROMBUS",
             (0.0, 0.30, 0.1025), 0.03, M["text_light"])

    # Steckdosen mit je einer Abdeckung. Index = Zeile * Spalten + Spalte, wie im Spiel.
    for row in range(HALL_C_SOCKET_ROWS):
        for col in range(HALL_C_SOCKET_COLS):
            idx = row * HALL_C_SOCKET_COLS + col
            sx, sy, sz = socket_pos(row, col)

            sock = GPart(f"hall_c_subpanel_Socket_{idx + 1}")
            sock.gbox((sx, sy, sz), (0.058, 0.058, 0.012), M["hall_c_socket"])
            ob = sock.build(coll, root)
            ob["dct_socket_index"] = idx

            cover = GPart(f"hall_c_subpanel_SocketCover_{idx + 1}")
            cover.gbox((sx, sy, 0.134), (0.062, 0.062, 0.006), M["hall_c_cover"])
            ob = cover.build(coll, root)
            ob["dct_socket_index"] = idx

    return root