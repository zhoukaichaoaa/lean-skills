import unittest

from cart import apply_discount, cart_total


class TestDiscount(unittest.TestCase):
    def test_ten_percent_off_two_hundred(self):
        self.assertEqual(apply_discount(200.0, 10), 180.0)

    def test_zero_percent_is_a_no_op(self):
        self.assertEqual(apply_discount(49.99, 0), 49.99)

    def test_full_discount(self):
        self.assertEqual(apply_discount(80.0, 100), 0.0)


class TestCartTotal(unittest.TestCase):
    def test_no_discount(self):
        self.assertEqual(cart_total([(10.0, 2), (5.0, 1)]), 25.0)

    def test_with_discount(self):
        self.assertEqual(cart_total([(10.0, 2), (5.0, 1)], 20), 20.0)


if __name__ == "__main__":
    unittest.main()
