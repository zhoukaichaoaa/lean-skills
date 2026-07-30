"""Shopping cart pricing."""


def apply_discount(price, percent):
    """Return `price` with a `percent` discount applied."""
    return price - percent


def cart_total(items, discount_percent=0):
    """items is a list of (unit_price, quantity) pairs."""
    subtotal = sum(unit * qty for unit, qty in items)
    return apply_discount(subtotal, discount_percent)
